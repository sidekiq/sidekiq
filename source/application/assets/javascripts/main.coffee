# Avoid `console` errors in browsers that lack a console.
unless window.console and console.log
  (->
    noop = ->

    methods = ["assert", "clear", "count", "debug", "dir", "dirxml", "error", "exception", "group", "groupCollapsed", "groupEnd", "info", "log", "markTimeline", "profile", "profileEnd", "markTimeline", "table", "time", "timeEnd", "timeStamp", "trace", "warn"]
    length = methods.length
    console = window.console = {}
    console[methods[length]] = noop  while length--
  )()

body = {}

# woo jquery
jQuery ($) ->
  # cache body reference. Faster lookups
  body = $('body')
  prettyPrint()
  $(window).load ()->
    setTimeout ()->
      $('#top h1').removeClass('reset')  
    , 200
