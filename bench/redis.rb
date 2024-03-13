require "benchmark/ips"
require "sidekiq"


SMALL = {"fe8"=>{:queue=>"default", :payload=>"{\"retry\":true,\"queue\":\"default\",\"wrapped\":\"SomeJob\",\"args\":[{\"job_class\":\"SomeJob\",\"job_id\":\"9ee78013-5e27-4c49-bdbb-89be433b9917\",\"provider_job_id\":null,\"queue_name\":\"default\",\"priority\":null,\"arguments\":[12],\"executions\":0,\"exception_executions\":{},\"locale\":\"en\",\"timezone\":\"UTC\",\"enqueued_at\":\"2024-03-13T17:53:57.597734000Z\",\"scheduled_at\":null}],\"class\":\"ActiveJob::QueueAdapters::SidekiqAdapter::JobWrapper\",\"jid\":\"3b16506254773135fac54699\",\"created_at\":1710352437.598104,\"enqueued_at\":1710352437.598944}", :run_at=>1710352437}}
CURSTATE = {"fe8"=>{:queue=>"default", :payload=>"{\"retry\":true,\"queue\":\"default\",\"wrapped\":\"SomeJob\",\"args\":[{\"job_class\":\"SomeJob\",\"job_id\":\"9ee78013-5e27-4c49-bdbb-89be433b9917\",\"provider_job_id\":null,\"queue_name\":\"default\",\"priority\":null,\"arguments\":[12],\"executions\":0,\"exception_executions\":{},\"locale\":\"en\",\"timezone\":\"UTC\",\"enqueued_at\":\"2024-03-13T17:53:57.597734000Z\",\"scheduled_at\":null}],\"class\":\"ActiveJob::QueueAdapters::SidekiqAdapter::JobWrapper\",\"jid\":\"3b16506254773135fac54699\",\"created_at\":1710352437.598104,\"enqueued_at\":1710352437.598944}", :run_at=>1710352437}, "f6g"=>{:queue=>"default", :payload=>"{\"retry\":true,\"queue\":\"default\",\"wrapped\":\"SomeJob\",\"args\":[{\"job_class\":\"SomeJob\",\"job_id\":\"ce421b11-bef0-440e-b59f-5fc267e76cb9\",\"provider_job_id\":null,\"queue_name\":\"default\",\"priority\":null,\"arguments\":[12],\"executions\":0,\"exception_executions\":{},\"locale\":\"en\",\"timezone\":\"UTC\",\"enqueued_at\":\"2024-03-13T17:53:58.056616000Z\",\"scheduled_at\":null}],\"class\":\"ActiveJob::QueueAdapters::SidekiqAdapter::JobWrapper\",\"jid\":\"be0b0e608ad269ece71918b9\",\"created_at\":1710352438.056737,\"enqueued_at\":1710352438.056885}", :run_at=>1710352438}, "f64"=>{:queue=>"default", :payload=>"{\"retry\":true,\"queue\":\"default\",\"wrapped\":\"SomeJob\",\"args\":[{\"job_class\":\"SomeJob\",\"job_id\":\"8b0f9ec8-f77b-4d53-8b6c-1939590203cf\",\"provider_job_id\":null,\"queue_name\":\"default\",\"priority\":null,\"arguments\":[12],\"executions\":0,\"exception_executions\":{},\"locale\":\"en\",\"timezone\":\"UTC\",\"enqueued_at\":\"2024-03-13T17:53:58.424281000Z\",\"scheduled_at\":null}],\"class\":\"ActiveJob::QueueAdapters::SidekiqAdapter::JobWrapper\",\"jid\":\"5acb15477d6dd393511437d5\",\"created_at\":1710352438.424384,\"enqueued_at\":1710352438.4245021}", :run_at=>1710352438}, "f5c"=>{:queue=>"default", :payload=>"{\"retry\":true,\"queue\":\"default\",\"wrapped\":\"SomeJob\",\"args\":[{\"job_class\":\"SomeJob\",\"job_id\":\"2d92e9e2-e25b-4795-bb32-d2acc344e959\",\"provider_job_id\":null,\"queue_name\":\"default\",\"priority\":null,\"arguments\":[12],\"executions\":0,\"exception_executions\":{},\"locale\":\"en\",\"timezone\":\"UTC\",\"enqueued_at\":\"2024-03-13T17:53:58.658736000Z\",\"scheduled_at\":null}],\"class\":\"ActiveJob::QueueAdapters::SidekiqAdapter::JobWrapper\",\"jid\":\"f187d1c9310b4ca1cd6f4abe\",\"created_at\":1710352438.658849,\"enqueued_at\":1710352438.6589818}", :run_at=>1710352438}, "f50"=>{:queue=>"default", :payload=>"{\"retry\":true,\"queue\":\"default\",\"wrapped\":\"SomeJob\",\"args\":[{\"job_class\":\"SomeJob\",\"job_id\":\"b7a1fc71-ba88-49e7-b279-f2369bd73514\",\"provider_job_id\":null,\"queue_name\":\"default\",\"priority\":null,\"arguments\":[12],\"executions\":0,\"exception_executions\":{},\"locale\":\"en\",\"timezone\":\"UTC\",\"enqueued_at\":\"2024-03-13T17:53:58.893776000Z\",\"scheduled_at\":null}],\"class\":\"ActiveJob::QueueAdapters::SidekiqAdapter::JobWrapper\",\"jid\":\"37b0ef0024af5163f3172d10\",\"created_at\":1710352438.893874,\"enqueued_at\":1710352438.8939872}", :run_at=>1710352438}, "f48"=>{:queue=>"default", :payload=>"{\"retry\":true,\"queue\":\"default\",\"wrapped\":\"SomeJob\",\"args\":[{\"job_class\":\"SomeJob\",\"job_id\":\"3ce721a8-3f56-4689-a0be-f32517d3ad2f\",\"provider_job_id\":null,\"queue_name\":\"default\",\"priority\":null,\"arguments\":[12],\"executions\":0,\"exception_executions\":{},\"locale\":\"en\",\"timezone\":\"UTC\",\"enqueued_at\":\"2024-03-13T17:53:59.115008000Z\",\"scheduled_at\":null}],\"class\":\"ActiveJob::QueueAdapters::SidekiqAdapter::JobWrapper\",\"jid\":\"f56d43ee034a18fa78655c6d\",\"created_at\":1710352439.115071,\"enqueued_at\":1710352439.115139}", :run_at=>1710352439}, "f3w"=>{:queue=>"default", :payload=>"{\"retry\":true,\"queue\":\"default\",\"wrapped\":\"SomeJob\",\"args\":[{\"job_class\":\"SomeJob\",\"job_id\":\"0f22f7c6-7980-4452-88b4-9be8e6c96487\",\"provider_job_id\":null,\"queue_name\":\"default\",\"priority\":null,\"arguments\":[12],\"executions\":0,\"exception_executions\":{},\"locale\":\"en\",\"timezone\":\"UTC\",\"enqueued_at\":\"2024-03-13T17:53:59.327203000Z\",\"scheduled_at\":null}],\"class\":\"ActiveJob::QueueAdapters::SidekiqAdapter::JobWrapper\",\"jid\":\"de4c4c11f490f21b31e5fd99\",\"created_at\":1710352439.3273118,\"enqueued_at\":1710352439.327444}", :run_at=>1710352439}, "f34"=>{:queue=>"default", :payload=>"{\"retry\":true,\"queue\":\"default\",\"wrapped\":\"SomeJob\",\"args\":[{\"job_class\":\"SomeJob\",\"job_id\":\"e5b398ae-1358-415b-9c05-36a47478f3cc\",\"provider_job_id\":null,\"queue_name\":\"default\",\"priority\":null,\"arguments\":[12],\"executions\":0,\"exception_executions\":{},\"locale\":\"en\",\"timezone\":\"UTC\",\"enqueued_at\":\"2024-03-13T17:53:59.536843000Z\",\"scheduled_at\":null}],\"class\":\"ActiveJob::QueueAdapters::SidekiqAdapter::JobWrapper\",\"jid\":\"e8806426ef98fdbcfdfe4dca\",\"created_at\":1710352439.53694,\"enqueued_at\":1710352439.537063}", :run_at=>1710352439}, "f2s"=>{:queue=>"default", :payload=>"{\"retry\":true,\"queue\":\"default\",\"wrapped\":\"SomeJob\",\"args\":[{\"job_class\":\"SomeJob\",\"job_id\":\"88e914ee-b297-4cc2-b57f-b7a3bb180103\",\"provider_job_id\":null,\"queue_name\":\"default\",\"priority\":null,\"arguments\":[12],\"executions\":0,\"exception_executions\":{},\"locale\":\"en\",\"timezone\":\"UTC\",\"enqueued_at\":\"2024-03-13T17:53:59.765240000Z\",\"scheduled_at\":null}],\"class\":\"ActiveJob::QueueAdapters::SidekiqAdapter::JobWrapper\",\"jid\":\"45f264e8c81ebb51fa93fafb\",\"created_at\":1710352439.7654212,\"enqueued_at\":1710352439.76562}", :run_at=>1710352439}, "f20"=>{:queue=>"default", :payload=>"{\"retry\":true,\"queue\":\"default\",\"wrapped\":\"SomeJob\",\"args\":[{\"job_class\":\"SomeJob\",\"job_id\":\"ac5cc293-a287-45fd-bf49-e775a055f687\",\"provider_job_id\":null,\"queue_name\":\"default\",\"priority\":null,\"arguments\":[12],\"executions\":0,\"exception_executions\":{},\"locale\":\"en\",\"timezone\":\"UTC\",\"enqueued_at\":\"2024-03-13T17:53:59.963088000Z\",\"scheduled_at\":null}],\"class\":\"ActiveJob::QueueAdapters::SidekiqAdapter::JobWrapper\",\"jid\":\"5fe7ab32f17f75076dce66a9\",\"created_at\":1710352439.963197,\"enqueued_at\":1710352439.96333}", :run_at=>1710352439}, "f1o"=>{:queue=>"default", :payload=>"{\"retry\":true,\"queue\":\"default\",\"wrapped\":\"SomeJob\",\"args\":[{\"job_class\":\"SomeJob\",\"job_id\":\"c775b9be-3a06-42cd-b150-b899f918759b\",\"provider_job_id\":null,\"queue_name\":\"default\",\"priority\":null,\"arguments\":[12],\"executions\":0,\"exception_executions\":{},\"locale\":\"en\",\"timezone\":\"UTC\",\"enqueued_at\":\"2024-03-13T17:54:00.179378000Z\",\"scheduled_at\":null}],\"class\":\"ActiveJob::QueueAdapters::SidekiqAdapter::JobWrapper\",\"jid\":\"4c2d8adfa5f1a5326d400006\",\"created_at\":1710352440.179494,\"enqueued_at\":1710352440.179615}", :run_at=>1710352440}, "f0w"=>{:queue=>"default", :payload=>"{\"retry\":true,\"queue\":\"default\",\"wrapped\":\"SomeJob\",\"args\":[{\"job_class\":\"SomeJob\",\"job_id\":\"c82ed5af-63bd-4bdd-bc4a-6b8fe1e94235\",\"provider_job_id\":null,\"queue_name\":\"default\",\"priority\":null,\"arguments\":[12],\"executions\":0,\"exception_executions\":{},\"locale\":\"en\",\"timezone\":\"UTC\",\"enqueued_at\":\"2024-03-13T17:54:00.424711000Z\",\"scheduled_at\":null}],\"class\":\"ActiveJob::QueueAdapters::SidekiqAdapter::JobWrapper\",\"jid\":\"aa8d8867a3973afc8c7c2775\",\"created_at\":1710352440.4248161,\"enqueued_at\":1710352440.4249458}", :run_at=>1710352440}, "f0k"=>{:queue=>"default", :payload=>"{\"retry\":true,\"queue\":\"default\",\"wrapped\":\"SomeJob\",\"args\":[{\"job_class\":\"SomeJob\",\"job_id\":\"3a635b75-35c1-4567-a3dd-a5f73557b0d9\",\"provider_job_id\":null,\"queue_name\":\"default\",\"priority\":null,\"arguments\":[12],\"executions\":0,\"exception_executions\":{},\"locale\":\"en\",\"timezone\":\"UTC\",\"enqueued_at\":\"2024-03-13T17:54:00.659566000Z\",\"scheduled_at\":null}],\"class\":\"ActiveJob::QueueAdapters::SidekiqAdapter::JobWrapper\",\"jid\":\"6f8e676bfb5f1fb22b8f327c\",\"created_at\":1710352440.6596632,\"enqueued_at\":1710352440.65977}", :run_at=>1710352440}, "fs8"=>{:queue=>"default", :payload=>"{\"retry\":true,\"queue\":\"default\",\"wrapped\":\"SomeJob\",\"args\":[{\"job_class\":\"SomeJob\",\"job_id\":\"411a36cf-ea93-4635-88e9-b0db44ee5315\",\"provider_job_id\":null,\"queue_name\":\"default\",\"priority\":null,\"arguments\":[12],\"executions\":0,\"exception_executions\":{},\"locale\":\"en\",\"timezone\":\"UTC\",\"enqueued_at\":\"2024-03-13T17:54:00.900850000Z\",\"scheduled_at\":null}],\"class\":\"ActiveJob::QueueAdapters::SidekiqAdapter::JobWrapper\",\"jid\":\"a9b73c1f9420abee04889b3b\",\"created_at\":1710352440.900956,\"enqueued_at\":1710352440.901083}", :run_at=>1710352440}, "frw"=>{:queue=>"default", :payload=>"{\"retry\":true,\"queue\":\"default\",\"wrapped\":\"SomeJob\",\"args\":[{\"job_class\":\"SomeJob\",\"job_id\":\"2333fa30-4a51-45af-b1f1-40ba079c659f\",\"provider_job_id\":null,\"queue_name\":\"default\",\"priority\":null,\"arguments\":[12],\"executions\":0,\"exception_executions\":{},\"locale\":\"en\",\"timezone\":\"UTC\",\"enqueued_at\":\"2024-03-13T17:54:01.155567000Z\",\"scheduled_at\":null}],\"class\":\"ActiveJob::QueueAdapters::SidekiqAdapter::JobWrapper\",\"jid\":\"f84b6e9ff637f6cf9687a355\",\"created_at\":1710352441.1556711,\"enqueued_at\":1710352441.155802}", :run_at=>1710352441}, "fr4"=>{:queue=>"default", :payload=>"{\"retry\":true,\"queue\":\"default\",\"wrapped\":\"SomeJob\",\"args\":[{\"job_class\":\"SomeJob\",\"job_id\":\"e6e7cd8a-d81f-487a-a2c1-515f8057f18d\",\"provider_job_id\":null,\"queue_name\":\"default\",\"priority\":null,\"arguments\":[12],\"executions\":0,\"exception_executions\":{},\"locale\":\"en\",\"timezone\":\"UTC\",\"enqueued_at\":\"2024-03-13T17:54:01.407810000Z\",\"scheduled_at\":null}],\"class\":\"ActiveJob::QueueAdapters::SidekiqAdapter::JobWrapper\",\"jid\":\"612943401eb81471e92afc3b\",\"created_at\":1710352441.407915,\"enqueued_at\":1710352441.4080372}", :run_at=>1710352441}}

totalo = 0
totalt = 0

Benchmark.ips do |x|
  key = "rubygems/core_ext/kernel_require"
  x.report("original") do
    curstate = CURSTATE.dup

    Sidekiq.redis do |conn|
      # work is the current set of executing jobs
      work_key = "#{key}:work"
      conn.pipelined do |transaction|
        transaction.unlink(work_key)
        a = Time.now
        curstate.each_pair do |tid, hash|
          transaction.hset work_key, tid, Sidekiq.dump_json(hash)
        end
        b = Time.now
        totalo += (b - a)
        transaction.expire(work_key, 60)
      end
    end
  end
  x.report("tuned") do
    curstate = CURSTATE.dup
    curstate.transform_values! { |val| Sidekiq.dump_json(val) }

    Sidekiq.redis do |conn|
      # work is the current set of executing jobs
      work_key = "#{key}:work"
      conn.multi do |transaction|
        transaction.unlink(work_key)
        transaction.hset(work_key, curstate) if curstate.size > 0
        transaction.expire(work_key, 60)
      end
    end
  end
  x.report("original/small") do
    curstate = SMALL.dup

    Sidekiq.redis do |conn|
      # work is the current set of executing jobs
      work_key = "#{key}:work"
      conn.pipelined do |transaction|
        transaction.unlink(work_key)
        curstate.each_pair do |tid, hash|
          transaction.hset work_key, tid, Sidekiq.dump_json(hash)
        end
        transaction.expire(work_key, 60)
      end
    end
  end
  x.report("tuned/small") do
    curstate = SMALL.dup
    curstate.transform_values! { |val| Sidekiq.dump_json(val) }

    Sidekiq.redis do |conn|
      # work is the current set of executing jobs
      work_key = "#{key}:work"
      conn.pipelined do |transaction|
        transaction.unlink(work_key)
        transaction.call("hset", work_key, curstate) if curstate.size > 0
        transaction.expire(work_key, 60)
      end
    end
  end
end

p [totalo, totalt]