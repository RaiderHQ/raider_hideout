RSpec.shared_examples "a webhook notifier" do
  it "treats 5xx as retryable" do
    stub_request(:post, url).to_return(status: 500)
    expect { notifier.deliver(message) }.to raise_error(Notifications::RetryableError)
  end

  it "carries Retry-After on 429" do
    stub_request(:post, url).to_return(status: 429, headers: { "Retry-After" => "30" })
    expect { notifier.deliver(message) }.to raise_error(Notifications::RetryableError) { |e| expect(e.retry_after).to eq(30) }
  end

  it "treats timeouts as retryable" do
    stub_request(:post, url).to_timeout
    expect { notifier.deliver(message) }.to raise_error(Notifications::RetryableError)
  end

  [ 404, 410 ].each do |status|
    it "treats #{status} as permanent" do
      stub_request(:post, url).to_return(status: status)
      expect { notifier.deliver(message) }.to raise_error(Notifications::PermanentError)
    end
  end

  it "never leaks the webhook url in errors" do
    stub_request(:post, url).to_raise(SocketError.new("failed to connect to #{url}"))
    expect { notifier.deliver(message) }.to raise_error(Notifications::RetryableError) { |e|
      expect(e.message).not_to include(url)
    }
  end

  it "leaves no secret fragment when the response body echoes the webhook url near the cut" do
    secret = channel.webhook_url.split("?").first.split("/").last(2).join("/")
    [ url, url.gsub("/", "\\/") ].each do |echoed|
      stub_request(:post, url).to_return(status: 400, body: "#{'x' * 185}#{echoed}")
      expect { notifier.deliver(message) }.to raise_error(Notifications::PermanentError) { |e|
        expect(e.message).to start_with("HTTP 400: ")
        expect(e.message).not_to include(secret)
        expect(e.message).not_to include(url[0, 40])
        expect(e.message.length).to be <= 210
      }
    end
  end

  it "redacts then truncates server errors too" do
    stub_request(:post, url).to_return(status: 503, body: "down #{url}")
    expect { notifier.deliver(message) }.to raise_error(Notifications::RetryableError) { |e|
      expect(e.message).to start_with("HTTP 503: down ")
      expect(e.message).not_to include(url)
    }
  end
end
