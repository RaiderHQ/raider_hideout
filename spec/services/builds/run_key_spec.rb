require "rails_helper"

RSpec.describe Builds::RunKey do
  describe ".from_ci" do
    it "builds the key from repository and build_id" do
      expect(described_class.from_ci("provider" => "github_actions", "repository" => "acme/shop", "build_id" => "42")).to eq("github_actions:acme/shop:42")
    end

    it "is nil for other providers" do
      expect(described_class.from_ci("provider" => "azure_pipelines", "repository" => "a/b", "build_id" => "42")).to be_nil
    end

    it "is nil without repository and build_key" do
      expect(described_class.from_ci("provider" => "github_actions", "build_id" => "42")).to be_nil
    end

    it "falls back to the build_key" do
      expect(described_class.from_ci("provider" => "github_actions", "build_id" => "42", "build_key" => "github_actions:acme/shop:42:3")).to eq("github_actions:acme/shop:42")
    end

    it "is nil for a non-numeric build_id" do
      expect(described_class.from_ci("provider" => "github_actions", "repository" => "acme/shop", "build_id" => "4x2")).to be_nil
    end

    it "never raises on odd input" do
      [ nil, "str", 5, [], { "provider" => { "a" => 1 } },
        { "provider" => "github_actions", "repository" => { "a" => 1 }, "build_id" => 10**40 },
        { "provider" => "github_actions", "repository" => "a/b", "build_id" => 42 },
        { "provider" => "github_actions", "build_key" => 7 },
        { "provider" => "github_actions", "repository" => "a/b", "build_id" => "9" * 30 } ].each do |ci|
        expect { described_class.from_ci(ci) }.not_to raise_error
      end
      expect(described_class.from_ci({ "provider" => "github_actions", "repository" => "a/b", "build_id" => 10**40 })).to be_nil
      expect(described_class.from_ci({ "provider" => "github_actions", "repository" => "a/b", "build_id" => "9" * 30 })).to be_nil
    end
  end

  describe ".from_build_key" do
    it "splits run key and attempt" do
      expect(described_class.from_build_key("github_actions:acme/shop:42:2")).to eq([ "github_actions:acme/shop:42", 2 ])
    end

    it "is nil without an attempt, for other providers, or a malformed repository" do
      expect(described_class.from_build_key("github_actions:acme/shop:42")).to be_nil
      expect(described_class.from_build_key("azure_pipelines:x/y/z:42:1")).to be_nil
      expect(described_class.from_build_key("github_actions:a:b:c/d:42:2")).to be_nil
    end

    it "is nil for non-strings" do
      expect(described_class.from_build_key(nil)).to be_nil
      expect(described_class.from_build_key({ "a" => 1 })).to be_nil
    end
  end

  describe ".attempt" do
    it "parses positive integers" do
      expect(described_class.attempt("3")).to eq(3)
      expect(described_class.attempt(4)).to eq(4)
    end

    it "falls back to 1" do
      [ "0", "-2", "abc", "99999999999", nil, "", {}, [ 1 ], 10**30, 2.5 ].each do |value|
        expect(described_class.attempt(value)).to eq(1)
      end
    end
  end
end
