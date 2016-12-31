require 'redis'

# Push three different types of jobs into Redis
r = Redis.new
r.flushdb
r.lpush "queue:default", '{"class":"ExitWorker","args":[],"retry":true,"queue":"default","jid":"4c51e497bbfea959deee0567","created_at":1479409542.279716,"enqueued_at":1479409542.279781}'
r.lpush "queue:default", '{"class":"ActiveJob::QueueAdapters::SidekiqAdapter::JobWrapper","wrapped":"ExitJob","queue":"default","args":[{"job_class":"ExitJob","job_id":"f8a11fa4-753e-4567-838e-74009ee25cb2","queue_name":"default","priority":null,"arguments":[],"locale":"en"}],"retry":true,"jid":"d020316e37c17bbcd5d360b1","created_at":1479409368.005358,"enqueued_at":1479409368.0056908}'
r.lpush "queue:default", '{"class":"Sidekiq::Extensions::DelayedClass","args":["---\n- !ruby/class \'Exiter\'\n- :run\n- []\n"],"retry":true,"queue":"default","jid":"6006486330d4a27a03593d09","created_at":1479409495.87069,"enqueued_at":1479409495.870754}'
