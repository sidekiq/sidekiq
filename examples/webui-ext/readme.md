# Web UI Extensions in Sidekiq 7.3 and 8.0

This is an example of how to extend Sidekiq's Web UI to add your own tab.

## Initialization

The Ruby code for your extension goes in `lib/` like any normal Rubygem.
When the user includes the `my_gem` gem within their bundle, Bundler will call `require "my_gem"` which corresponds to `lib/my_gem.rb` in your project.
This file should **not** require any web code or assets because you don't know if you're running within a Sidekiq process or a Web process.

> Don't require your web extensions in Sidekiq's initializer. This is a common mistake.

Your web extension should be activated by the user calling `require "my_gem/web"` in Rails' `config/routes.rb` as that guarantees we are in a Web process. TODO usage in other web frameworks?

## Registration

Your Web extension must register itself with Sidekiq::Web to appear in the Sidekiq UI.
See `lib/sidekiq-redis_info/web.rb` for an example.

## Content Security

Sidekiq 7.3 and 8.0 explicitly lock down the Web UI to prevent XSS and malicious content injection.
In Sidekiq 7.3, the Web UI no longer allows embedding JavaScript directly on the HTML page via
`<script>...code...</script>`. In Sidekiq 8.0, inline styling via `<style>...css...</style>` will not work.

### JavaScript

JavaScript must be packaged in predefined .js files with a per-request nonce that proves it was rendered by the webapp:

```html
<script type="text/javascript" src="<%= root_path %>my_gem/js/somefile.js" nonce="<%= csp_nonce %>"></script>
```

Sidekiq provides a `script_tag` to handle these details.

```erb
<%= script_tag "my_gem/js/somefile.js" %>
```

### CSS

Static CSS must be linked with the nonce:

```
<link href="<%= root_path %>my_gem/css/somefile.css" media="screen" rel="stylesheet" type="text/css" nonce="<%= csp_nonce %>" />
```

You can dynamically adjust styling with javascript:

```
# will not work
<div style="width: 12%">

# will work
<div class="foobar" data-width="12">

# in an included .js file
document.querySelectorAll('.foobar').forEach(bar => { bar.style.width = bar.dataset.width + "%"})
```

Sidekiq provides a `style_tag` to handle these details.

```erb
<%= style_tag "my_gem/css/somefile.css" %>
```