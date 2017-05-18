# (m)Ruby Concurrently

TODO

## Ruby Installation

Add this line to your application's Gemfile:

```ruby
gem 'concurrently'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install concurrently

## mruby Installation

To directly add it to an mruby build config or GemBox:
```ruby
MRuby::Build.new do |conf| # or MRuby::GemBox.new do |conf|
  conf.gem github: 'christopheraue/m-ruby-concurrently'
end
```

To use it in an mruby gem:
```ruby
MRuby::Gem::Specification.new('mruby-your_gem') do |spec|
  spec.add_dependency 'mruby-concurrently', github: 'christopheraue/m-ruby-concurrently'
end
```

## Usage

TODO

## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).

