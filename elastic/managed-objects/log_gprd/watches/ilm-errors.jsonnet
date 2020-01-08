PUT _watcher/watch/test
{
  "trigger" : { "schedule" : { "interval" : "1m" } },
  "input": {
    "http": {
      "request": {
        "host": "e8fabf53b73247e98df7c355d6a782fc.us-central1.gcp.cloud.es.io",
        "port": 9243,
        "path": "/*/_ilm/explain",
        "scheme": "https"
      }
    }
  },
  "condition" : {
    "script" :
    """
      return ctx.payload.message.indexOf('ERROR') != 0
    """
  },
  "actions" : {
    "my_log" : {
      "logging" : {
        "text" : "Found ILM errors."
      }
    }
  }
}