# Guard + RSpec configuration.
# More info at https://github.com/guard/guard and https://github.com/guard/guard-rspec

require "ostruct"

guard :rspec, cmd: "bundle exec rspec" do
  # Run the full suite when core spec config changes.
  watch(%r{^\.rspec$})                    { "spec" }
  watch(%r{^spec/spec_helper\.rb$})       { "spec" }
  watch(%r{^spec/rails_helper\.rb$})      { "spec" }
  watch(%r{^spec/support/.+\.rb$})        { "spec" }

  # Re-run a spec file if it changed.
  watch(%r{^spec/.+_spec\.rb$})

  # Map changes in app/lib files to their corresponding specs.
  watch(%r{^app/models/(.+)\.rb$})        { |m| "spec/models/#{m[1]}_spec.rb" }
  watch(%r{^app/services/(.+)\.rb$})      { |m| "spec/services/#{m[1]}_spec.rb" }
  watch(%r{^app/jobs/(.+)\.rb$})          { |m| "spec/jobs/#{m[1]}_spec.rb" }
  # Sidekiq workers live in app/sidekiq/, but we test them under spec/jobs/.
  watch(%r{^app/sidekiq/(.+)\.rb$})       { |m| "spec/jobs/#{m[1]}_spec.rb" }
  watch(%r{^lib/(.+)\.rb$})               { |m| "spec/lib/#{m[1]}_spec.rb" }

  # Rails-ish mappings.
  watch(%r{^app/controllers/(.+)_controller\.rb$}) { |m| "spec/requests/#{m[1]}_spec.rb" }

  # If routes change, re-run request specs (or entire suite if none exist).
  watch(%r{^config/routes\.rb$}) do
    Dir.glob("spec/requests/**/*_spec.rb").presence || "spec"
  end

  # If factories change, it’s usually safest to re-run the suite.
  watch(%r{^spec/factories/.+\.rb$})      { "spec" }
end
