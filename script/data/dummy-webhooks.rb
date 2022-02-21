#!/usr/bin/env ruby
begin

  $LOAD_PATH << "#{Dir.pwd}/lib"
  require "pact_broker/test/http_test_data_builder"
  require "semantic_logger"

  base_url = ENV["PACT_BROKER_BASE_URL"] || "http://localhost:9292"

  SemanticLogger.add_appender(io: $stdout)

  http_client = Faraday.new(url: base_url) do |builder|
    #builder.response :logger, SemanticLogger['Faraday'], { headers: true, bodies: true }
    builder.adapter :net_http
  end

  CONSUMER_NAME = "consumer-1"
  PROVIDER_NAME = "provider-1"

  webhook_request_body = {
    "message" => "This is the webhook request body. These are some of the details about the pact that just got published.",
    "pactUrl" => "${pactbroker.pactUrl}",
    "eventName" => "${pactbroker.eventName}",
    "consumerName" => "${pactbroker.consumerName}",
    "consumerVersionNumber" => "${pactbroker.consumerVersionNumber}",
    "providerVersionBranch" => "${pactbroker.providerVersionBranch}",
    "providerName" => "${pactbroker.providerName}",
    "consumerVersionBranch" => "${pactbroker.consumerVersionBranch}",
  }

  td = PactBroker::Test::HttpTestDataBuilder.new(base_url)
  td.create_global_webhook_for_contract_changed(uuid: "72b78b05-9509-4465-ba8b-040605f6d634", url: "https://this-domain-does-not-exist", body: webhook_request_body)
    .delete_pacticipant(CONSUMER_NAME)
    .delete_pacticipant(PROVIDER_NAME)
    .publish_pact(consumer: CONSUMER_NAME, consumer_version: "1", provider: PROVIDER_NAME, content_id: "111")

  puts "Sleeping 7 seconds to wait for the webhook to execute..."
  sleep 7

  # get the triggered webhooks for the pact
  triggered_webhooks_response_body = JSON.parse(http_client.get("#{base_url}/pacts/provider/#{PROVIDER_NAME}/consumer/#{CONSUMER_NAME}/version/1/triggered-webhooks").body)

  # get the URLs of the log endpoints
  logs_urls =  triggered_webhooks_response_body["_embedded"]["triggeredWebhooks"].collect { | tw | tw["_links"]["pb:logs"]["href"] }

  # print out the logs
  requests = logs_urls.collect do | logs_url |
    logs = http_client.get(logs_url).body
    puts "\n\n"
    puts "LOGS from #{logs_url}\n--------------------------------------------"
    puts logs
    puts "\n--------------------------------------------"
  end

  # get the URLs of the webhooks that got triggered
  webhook_urls =  triggered_webhooks_response_body["_embedded"]["triggeredWebhooks"].collect { | tw | tw["_links"]["pb:webhook"]["href"]}

  # print out the webhook details
  requests = webhook_urls.collect do | webhook_url |
    webhook_response_body = JSON.parse(http_client.get(webhook_url).body)
    puts "\n\n"
    puts "WEBHOOK DEFINITION from #{webhook_url}\n"
    puts JSON.pretty_generate(webhook_response_body)
  end

rescue StandardError => e
  puts "#{e.class} #{e.message}"
  puts e.backtrace
  exit 1
end
