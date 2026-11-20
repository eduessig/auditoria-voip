class HealthController < ApplicationController
  def show
    ActiveRecord::Base.connection_pool.with_connection { |connection| connection.select_value("SELECT 1") }
    render json: { status: "ok", database: "ok" }
  rescue ActiveRecord::ActiveRecordError, PG::Error
    render json: { status: "unavailable", database: "unavailable" }, status: :service_unavailable
  end
end
