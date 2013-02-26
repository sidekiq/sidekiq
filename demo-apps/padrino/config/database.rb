##
# You can use other adapters like:
#
#   ActiveRecord::Base.configurations[:development] = {
#     :adapter   => 'mysql',
#     :encoding  => 'utf8',
#     :reconnect => true,
#     :database  => 'your_database',
#     :pool      => 5,
#     :username  => 'root',
#     :password  => '',
#     :host      => 'localhost',
#     :socket    => '/tmp/mysql.sock'
#   }
#
ActiveRecord::Base.configurations[:development] = {
  :adapter => 'sqlite3',
  :database => Padrino.root('db', 'padrino_app_development.db')

}

ActiveRecord::Base.configurations[:production] = {
  :adapter => 'sqlite3',
  :database => Padrino.root('db', 'padrino_app_production.db')

}

ActiveRecord::Base.configurations[:test] = {
  :adapter => 'sqlite3',
  :database => Padrino.root('db', 'padrino_app_test.db')

}

# Setup our logger
ActiveRecord::Base.logger = logger

# Raise exception on mass assignment protection for Active Record models.
ActiveRecord::Base.mass_assignment_sanitizer = :strict

# Log the query plan for queries taking more than this (works
# with SQLite, MySQL, and PostgreSQL).
ActiveRecord::Base.auto_explain_threshold_in_seconds = 0.5

# Include Active Record class name as root for JSON serialized output.
ActiveRecord::Base.include_root_in_json = false

# Store the full class name (including module namespace) in STI type column.
ActiveRecord::Base.store_full_sti_class = true

# Use ISO 8601 format for JSON serialized times and dates.
ActiveSupport.use_standard_json_time_format = true

# Don't escape HTML entities in JSON, leave that for the #json_escape helper
# if you're including raw JSON in an HTML page.
ActiveSupport.escape_html_entities_in_json = false

# Now we can establish connection with our db.
ActiveRecord::Base.establish_connection(ActiveRecord::Base.configurations[Padrino.env])
