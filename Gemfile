source "https://rubygems.org"

ruby "3.4.4"

gem "rails", "~> 7.1.6"
gem "pg", "~> 1.1"
gem "puma", ">= 5.0"
gem "sidekiq"
gem "redis"
gem "rack-cors"
gem "lograge"
gem "tzinfo-data", platforms: %i[ windows jruby ]
gem "bootsnap", require: false

group :development, :test do
  gem "debug", platforms: %i[ mri windows ]
  gem "rspec-rails"
  gem "factory_bot_rails"
  gem "faker"
end

group :test do
  gem "shoulda-matchers"
  gem "database_cleaner-active_record"
  gem "webmock"
end

