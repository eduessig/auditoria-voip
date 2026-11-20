require "rails_helper"

RSpec.describe "Application" do
  it "boots in API-only mode and connects to the test database" do
    expect(Rails.application.config.api_only).to be(true)
    expect(ActiveRecord::Base.connection.select_value("SELECT 1")).to eq(1)
  end
end
