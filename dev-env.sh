# Source before any ruby/rails/bundle command: source dev-env.sh
RUBY_VERSION_FOR_PROJECT="4.0.5"
RUBY_ABI="4.0.0"
export GEM_HOME="$HOME/.rubies/gems/${RUBY_VERSION_FOR_PROJECT}"
export GEM_PATH="$GEM_HOME:$HOME/.rubies/${RUBY_VERSION_FOR_PROJECT}/lib/ruby/gems/${RUBY_ABI}"
export PATH="$GEM_HOME/bin:$HOME/.rubies/${RUBY_VERSION_FOR_PROJECT}/bin:$PATH"
