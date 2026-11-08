# Loads one fastlane spec file REPEAT_SPEC_TIMES times, so a single rspec process runs its examples that many times.
# Copied to the root of a fastlane checkout and run with `bundle exec rspec repeat_spec.rb -e <example>`.
Integer(ENV.fetch("REPEAT_SPEC_TIMES")).times { load File.expand_path(ENV.fetch("REPEAT_SPEC_FILE")) }
