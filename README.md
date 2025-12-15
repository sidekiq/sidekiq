Run `bundle exec jekyll b` to build the site.

## Wiki

Sidekiq's github wiki is synchronized with this repo so the wiki content can be published to sidekiq.org.
You'll need to run these commands once to prepare your environment:

```
bundle
bundle exec rake wikisub
```

And then run this every time to synchronized and build the wiki pages. There are a few elements
which render differently between the two environments but it's 99% the same.

```
bundle exec rake wiki && bundle exec jekyll build
```

See specifically `_layouts/wiki.html`.