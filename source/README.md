# hull build stack
Foreword : this stack is heavily based on [l3ck](https://github.com/l3ck/sinatra-boilerplate)'s sinatra boilerplate.
peepz to him for it.

Here's a summary of our edits.

### hull's Additions

* Migrated many things to Settings, using [Settingslogic](https://github.com/binarylogic/settingslogic)
* Memcached made optional (using settings.yml)
* Made sprockets configuration a bit more flexible (using settings.yml)
* Added `lib` and `vendor` search paths for Sprockets. Add your extensions & libs, and reference them in vendor.css & vendor.js
* Vendored [bootstrap](http://twitter.github.com/bootstrap/)
* Added crossdomain.xml & 404 static file
* Migrated email notification sender & receiver in settings.yml
* Examples for compass spriting, and webfonts inclusion
* Ready for Pow…

For the rest, please checkout the original [here][l3ck](https://github.com/l3ck/sinatra-boilerplate)
