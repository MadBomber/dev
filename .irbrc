# linda-crnic/vbr_project/.irbrc
#
# Console helpers for the vbr clones under branches/. Loaded by ~/.irbrc's
# irb_load_up, which walks from / down to the PWD and loads every .irbrc it
# meets (HOME excepted), so a console started in branches/<name>/ gets this
# file after ~/.irbrc — `asgard stage console` and a plain `bin/rails console`
# alike. Nothing here replaces your own setup. Everything is read-only in
# intent except `purge_sample_data`: the staging console connects as
# vbr_dev_ro, and every other helper only ever SELECTs.
#
# The logic lives in DevConsole (module_function, so each piece can be
# exercised on its own); the bare top-level names are the console shorthand.
#
#   purge_sample_data [NAME] [dry_run: true]
#                          delete a sample study and its whole graph (development only)
#   load_em                eager load every model (STI subtypes too), connect, list them
#   lib_versions [pattern] every loaded VERSION / Version constant, labeled
#   models [pattern]       loaded ApplicationRecord models, optionally filtered
#   quiet!  / loud!        SQL echo off / on (starts off)
#   tables [pattern]       table names, optionally filtered (string or Regexp)
#   counts [pattern]       row counts per table, one round trip
#   cols TABLE_OR_MODEL    column name, type, nullability, default
#   sti [Model]            rows per STI type (default Artifact)
#   sql "SELECT ..."       run a query, print an aligned table, return the rows
#   recent Model [, n]     the n most recently created rows (default 10)
#   history RECORD         PaperTrail versions: when, who, what changed
#   doctors                active_record_doctor detectors and what each checks
#   doctor [NAME]          run every detector, or one, against this database
#   doctor_help NAME       a detector's configuration options
#   stage_help             this list
#
# The doctor helpers need the active_record_doctor gem, i.e. tmp/host/Gemfile.dev
# in effect; they say so and return nil when it is not.

module DevConsole
  SCHEMA_TABLES = %w[schema_migrations ar_internal_metadata].freeze

  module_function

  def conn = ActiveRecord::Base.connection

# --- loading ------------------------------------------------------------------

# Pull every ActiveRecord model into memory and verify the database is
# reachable, so the console can be poked at straight away. The console
# autoloads lazily (config.eager_load is false in development), which means
# `ApplicationRecord.descendants` is empty and STI subtypes such as AdultKit
# are unknown until something names them. One eager load of every Zeitwerk
# loader (app/, app/types, lib/ minus the ignored dirs) fixes that, then a
# trivial query confirms the primary connection. Returns the model list.
def load_em(print: true)
  Zeitwerk::Loader.eager_load_all
  conn.select_value("SELECT 1")
  list = models
  if print
    puts "#{list.size} models loaded against #{conn.current_database} (#{Rails.env})"
    print_table(%w[model table sti], models_rows(list))
  end
  list
end

# Concrete ApplicationRecord models currently loaded, sorted by name and
# optionally narrowed by a substring or Regexp on the name. Empty before
# `load_em` has run (or until the console has touched the model).
def models(pattern = nil)
  list = ApplicationRecord.descendants.reject(&:abstract_class?).sort_by(&:name)
  pattern ? list.select { filter([it.name], pattern).any? } : list
end

# Rows for the `load_em` table: name, table, and whether it is an STI
# subtype (its table belongs to a parent). Pure.
def models_rows(list)
  list.map { [it.name, it.table_name, it.base_class == it ? "" : "< #{it.base_class.name}"] }
end

  # --- library versions ---------------------------------------------------------

  VERSION_CONSTANTS = %i[VERSION Version].freeze

  # The as-loaded version of every library in the process: each named module
  # ObjectSpace knows about that defines VERSION or Version itself (inherited
  # constants ignored, so Foo::Bar does not repeat Foo's); Ruby 4 reports
  # itself as Ruby::VERSION. Only what has been required shows up — run
  # `load_em` first for the full stack. Narrowed by a substring or Regexp on
  # the label. Returns { label => version }; prints the aligned list unless
  # print: false.
  def lib_versions(pattern = nil, print: true)
    found  = ObjectSpace.each_object(Module).flat_map { version_entries(it) }.sort_by { |label, _| label.downcase }
    result = found.select { |label, _| filter([label], pattern).any? }.to_h
    print_table(%w[library version], result.to_a) if print
    result
  end

  # [[label, version], ...] for the VERSION / Version constants `mod` defines
  # directly. Anonymous modules, constants still waiting on autoload, and
  # values that do not read as a version are skipped. Pure.
  def version_entries(mod)
    name = Module.instance_method(:name).bind_call(mod) # some libraries override .name
    return [] if name.nil?

    VERSION_CONSTANTS.filter_map do |const|
      next unless mod.const_defined?(const, false) && !mod.autoload?(const, false)

      version = version_string(mod.const_get(const, false))
      ["#{name}::#{const}", version] if version
    end
  rescue NameError, LoadError
    []
  end

  # A version constant's value as a String: Strings and Gem::Versions as-is,
  # arrays dotted, and a Version module by its STRING or MAJOR.MINOR.PATCH
  # constants. nil when there is nothing version-like. Pure.
  def version_string(value)
    case value
    when String then value
    when Array  then value.join(".")
    when Module
      return value::STRING.to_s if value.const_defined?(:STRING, false)

      parts = %i[MAJOR MINOR PATCH TINY].select { value.const_defined?(it, false) }
      parts.empty? ? nil : parts.map { value.const_get(it, false) }.join(".")
    else value.to_s
    end
  end

  # --- SQL echo -----------------------------------------------------------------

  def quiet!
    ActiveRecord::Base.logger = nil
    puts "SQL echo off (loud! to restore)"
  end

  def loud!
    ActiveRecord::Base.logger = ActiveSupport::Logger.new($stdout)
    puts "SQL echo on"
  end

  # --- schema -------------------------------------------------------------------

  # Application tables (schema bookkeeping tables dropped), sorted, optionally
  # narrowed by a substring or Regexp.
  def tables(pattern = nil)
    names = conn.tables.sort - SCHEMA_TABLES
    filter(names, pattern)
  end

  # Exact row counts for `tables(pattern)` in a single UNION ALL round trip.
  # Returns { table => count }; prints the aligned list unless print: false.
  def counts(pattern = nil, print: true)
    names = tables(pattern)
    return {} if names.empty?

    rows   = conn.select_rows(counts_sql(names))
    result = rows.to_h { |t, n| [t, n.to_i] }
    print_table(%w[table rows], result.map { |t, n| [t, n] }) if print
    result
  end

  # The one query behind `counts`. Pure; names are quoted as identifiers.
  def counts_sql(names)
    names.map { "SELECT '#{it}' AS t, COUNT(*) AS n FROM #{conn.quote_table_name(it)}" }.join(" UNION ALL ")
  end

  # Columns of a table (or a model's table): name, SQL type, NULL?, default.
  def cols(table_or_model)
    table = table_or_model.respond_to?(:table_name) ? table_or_model.table_name : table_or_model.to_s
    rows  = conn.columns(table).map { [it.name, it.sql_type, it.null ? "null" : "not null", it.default.inspect] }
    print_table(%w[column type null default], rows)
    rows
  end

  # Rows per STI subtype, most numerous first. Works for any model with a
  # `type` column (Artifact, BiorepositoryProcess).
  def sti(model = Artifact)
    result = model.unscoped.group(:type).count.sort_by { |_, n| -n }
    print_table(%w[type rows], result)
    result.to_h
  end

  # --- data ---------------------------------------------------------------------

  # Run a query and show it as a table. Returns the rows (arrays).
  def sql(query)
    result = conn.select_all(query)
    print_table(result.columns, result.rows)
    result.rows
  end

  # The n most recently created rows of a model, newest first.
  def recent(model, n = 10)
    model.order(created_at: :desc).limit(n).to_a
  end

  # A record's PaperTrail trail: when, by whom, which attributes changed.
  def history(record)
    rows = record.versions.map do |v|
      [v.created_at&.strftime("%Y-%m-%d %H:%M"), v.event, v.whodunnit, changed_keys(v).join(", ")]
    end
    print_table(%w[at event whodunnit changed], rows)
    record.versions
  end

  # Attribute names a version changed, or [] when the version has no object_changes.
  def changed_keys(version)
    version.respond_to?(:object_changes) && version.object_changes ? version.changeset.keys : []
  end

  # --- sample data purge --------------------------------------------------------
  #
  # Removes a sample study and every row under it, naming no model: the tables
  # come from Study's has_many reflections (the per-type throughs included), the
  # delete order from the schema's foreign keys, and the ids from the study's own
  # associations. The study row goes last inside the same transaction, so the
  # foreign keys refuse the whole purge if a table was missed (DSVBR-193 holds
  # the reflection list complete; DSVBR-199 turns this into a command).
  #
  # Deletes are delete_all, so PaperTrail writes no destroy versions for the
  # rows; only the study's own destroy is versioned.

  SAMPLE_STUDY_NAMES = ["ABC-DS Synthetic", "CDP Sample"].freeze

  # Purge one sample study by name, or every SAMPLE_STUDY_NAMES study present
  # when name is nil. Refuses outside development and refuses a study that is
  # not a sample study unless force: true. dry_run: true does the deletes and
  # rolls back, so the counts are what a real run would remove. Returns
  # { study name => { table => rows deleted } }.
  def purge_sample_data(name = nil, dry_run: false, force: false)
    abort_purge("only runs in development (Rails.env is #{Rails.env}); force: true overrides") unless Rails.env.development? || force
    studies = purge_targets(name, force: force)
    return {} if studies.empty?

    studies.to_h do |study|
      deleted = purge_study(study, dry_run: dry_run)
      puts "#{dry_run ? "would delete" : "deleted"} #{study.name}:"
      print_table(%w[table rows], deleted.to_a)
      [study.name, deleted]
    end
  end

  # The studies a purge call names: the one called NAME, or every sample study
  # that exists. A name outside SAMPLE_STUDY_NAMES needs force: true. Pure
  # apart from the lookup.
  def purge_targets(name, force: false)
    if name.nil?
      found = Study.where(name: SAMPLE_STUDY_NAMES).to_a
      puts "no sample study present (#{SAMPLE_STUDY_NAMES.join(", ")})" if found.empty?
      return found
    end

    abort_purge("#{name.inspect} is not a sample study (#{SAMPLE_STUDY_NAMES.join(", ")}); force: true overrides") unless force || SAMPLE_STUDY_NAMES.include?(name)
    [Study.find_by!(name: name)]
  rescue ActiveRecord::RecordNotFound
    puts "no study named #{name.inspect}"
    []
  end

  # Delete everything under `study`, then the study, in one transaction.
  # Returns { table => rows deleted } including "studies" => 1.
  def purge_study(study, dry_run: false)
    ids_by_table = study_graph_ids(study)
    deleted = {}
    Study.transaction do
      study_delete_order(ids_by_table.keys).each do |table|
        klass, ids = ids_by_table[table]
        deleted[table] = klass.where(id: ids).delete_all
      end
      study.reload.destroy!
      deleted["studies"] = 1
      raise ActiveRecord::Rollback if dry_run
    end
    deleted
  end

  # Study's has_many reflections grouped by target table (several per-type
  # reflections share a table), PaperTrail's versions left out. Pure.
  def study_graph_reflections
    Study.reflect_on_all_associations(:has_many)
         .reject { it.klass == PaperTrail::Version }
         .group_by { it.klass.table_name }
  end

  # Every id the study reaches, plucked before any delete so the order does
  # not have to know about the polymorphic pointers (artifact -> detail,
  # connection -> auth strategy) that no foreign key records.
  # Returns { table => [klass, ids] }.
  def study_graph_ids(study)
    study_graph_reflections.to_h do |table, reflections|
      ids = reflections.flat_map { study.public_send(it.name).pluck(:id) }.uniq
      [table, [reflections.first.klass, ids]]
    end
  end

  # `tables` ordered so that no table is deleted while another still waiting
  # references it through a foreign key. Pure given the schema.
  def study_delete_order(tables)
    refs = tables.index_with { conn.foreign_keys(it).map(&:to_table) & tables }
    ordered = []
    remaining = tables.dup
    until remaining.empty?
      free = remaining.reject { |t| (remaining - [t]).any? { refs[it].include?(t) } }
      raise "foreign-key cycle among #{remaining.join(", ")}" if free.empty?

      ordered.concat(free.sort)
      remaining -= free
    end
    ordered
  end

  def abort_purge(reason)
    raise ArgumentError, "purge_sample_data: #{reason}"
  end

  # --- active_record_doctor -----------------------------------------------------
  #
  # An in-process front end to the gem's detectors — what `rake
  # active_record_doctor` runs — so a schema can be examined from the console
  # without a rake task or a writable database: detectors only read the models
  # and the information schema. Mirrors the gem's own rake task: the clone's
  # .active_record_doctor.rb when it has one, the gem defaults otherwise, and
  # an eager load first because detectors inspect every model.

  # True when the gem is loadable (tmp/host/Gemfile.dev in effect); otherwise
  # says what to do and returns false.
  def doctor_available?
    require "active_record_doctor"
    true
  rescue LoadError
    puts "active_record_doctor is not in this bundle — copy vbr_project/Gemfile.dev to tmp/host/ and restart the console."
    false
  end

  # Every detector with its description. Returns the names.
  def doctors
    return [] unless doctor_available?

    rows = ActiveRecordDoctor.detectors.map { |name, detector| [name, detector.description] }
    print_table(%w[detector description], rows)
    rows.map(&:first)
  end

  # Run every detector, or just `name` (a Symbol or String from `doctors`).
  # Problems print as the rake task prints them; returns true when none found.
  def doctor(name = nil)
    return unless doctor_available?

    Rails.application.eager_load! # detectors walk every model
    runner = doctor_runner
    result = name ? runner.run_one(name.to_sym) : runner.run_all
    puts result ? "active_record_doctor: no problems found#{" (#{name})" if name}" : "active_record_doctor: problems found — see above"
    result
  rescue KeyError
    puts "No detector named #{name.inspect}; `doctors` lists them."
    nil
  end

  # A detector's configuration options, as `rake active_record_doctor:NAME:help` shows them.
  def doctor_help(name)
    return unless doctor_available?

    doctor_runner.help(name.to_sym)
  rescue KeyError
    puts "No detector named #{name.inspect}; `doctors` lists them."
    nil
  end

  # The gem's Runner, configured as its rake task would configure it.
  def doctor_runner
    config = ActiveRecordDoctor.load_config_with_defaults(doctor_config_path)
    ActiveRecordDoctor::Runner.new(config: config, logger: ActiveRecordDoctor::Logger::Dummy.new, io: $stdout)
  end

  # Rails.root/.active_record_doctor.rb when it exists, else nil (gem defaults). Pure.
  def doctor_config_path(root = Rails.root)
    path = root.join(".active_record_doctor.rb")
    path.exist? ? path.to_s : nil
  end

  # --- presentation -------------------------------------------------------------

  # Keep the names matching `pattern` (String substring or Regexp); nil keeps all. Pure.
  def filter(names, pattern)
    case pattern
    when nil    then names
    when Regexp then names.grep(pattern)
    else             names.select { it.include?(pattern.to_s) }
    end
  end

  # Aligned text table. Pure apart from the puts; `format_table` is the testable part.
  def print_table(headers, rows)
    puts format_table(headers, rows)
  end

  def format_table(headers, rows)
    cells  = [headers.map(&:to_s)] + rows.map { |r| r.map(&:to_s) }
    widths = cells.transpose.map { |col| col.map(&:length).max }
    line   = ->(r) { r.each_with_index.map { |c, i| c.ljust(widths[i]) }.join("  ").rstrip }
    [line.(cells.first), widths.map { "-" * it }.join("  "), *cells.drop(1).map(&line)].join("\n")
  end

  def help
    puts <<~HELP
      purge_sample_data [NAME] [dry_run: true]   delete a sample study and its graph (development only)
      load_em               eager load every model, connect, list them
      lib_versions [pat]    loaded VERSION / Version constants (string or Regexp filter)
      models [pattern]      loaded models (string or Regexp filter)
      quiet! / loud!        SQL echo off / on
      tables [pattern]      table names (string or Regexp filter)
      counts [pattern]      row counts per table
      cols TABLE_OR_MODEL   columns: name, type, null, default
      sti [Model]           rows per STI type (default Artifact)
      sql "SELECT ..."      run a query, print it, return rows
      recent Model [, n]    newest n rows (default 10)
      history RECORD        PaperTrail versions
      doctors               active_record_doctor detectors
      doctor [NAME]         run every detector, or one
      doctor_help NAME      a detector's options
    HELP
  end
end

# Console shorthand: bare names that forward to DevConsole.
def purge_sample_data(name = nil, dry_run: false, force: false) = DevConsole.purge_sample_data(name, dry_run: dry_run, force: force)
def load_em(print: true) = DevConsole.load_em(print: print)
def lib_versions(pattern = nil, print: true) = DevConsole.lib_versions(pattern, print: print)
def models(pattern = nil) = DevConsole.models(pattern)
def quiet! = DevConsole.quiet!
def loud! = DevConsole.loud!
def tables(pattern = nil) = DevConsole.tables(pattern)
def counts(pattern = nil, print: true) = DevConsole.counts(pattern, print: print)
def cols(table_or_model) = DevConsole.cols(table_or_model)
def sti(model = Artifact) = DevConsole.sti(model)
def sql(query) = DevConsole.sql(query)
def recent(model, n = 10) = DevConsole.recent(model, n)
def history(record) = DevConsole.history(record)
def doctors = DevConsole.doctors
def doctor(name = nil) = DevConsole.doctor(name)
def doctor_help(name) = DevConsole.doctor_help(name)
def stage_help = DevConsole.help

if defined?(ActiveRecord::Base)
  DevConsole.quiet!
  puts "vbr_project/.irbrc loaded — stage_help lists the helpers"
end
