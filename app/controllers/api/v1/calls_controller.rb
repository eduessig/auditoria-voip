require "time"

module Api
  module V1
    class CallsController < ApplicationController
      FILTERS = %w[caller callee status started_at_from started_at_to page per_page].freeze

      def index
        unknown = request.query_parameters.keys - FILTERS
        raise ArgumentError if unknown.any?

        page = positive_integer("page", 1, 1_000_000)
        per_page = positive_integer("per_page", 20, 100)
        scope = Call.all
        %w[caller callee status].each do |field|
          next unless request.query_parameters.key?(field)
          value = request.query_parameters[field]
          raise ArgumentError unless value.is_a?(String) && value.present?
          raise ArgumentError if field == "status" && !Call::STATUSES.include?(value)
          scope = scope.where(field => value)
        end
        from = timestamp("started_at_from")
        to = timestamp("started_at_to")
        raise ArgumentError if from && to && from > to
        scope = scope.where("started_at >= ?", from) if from
        scope = scope.where("started_at <= ?", to) if to
        total = scope.count
        calls = scope.order(started_at: :desc, id: :desc).offset((page - 1) * per_page).limit(per_page)
        render json: { data: calls.map { |call| serialize(call) }, pagination: { page: page, per_page: per_page, total: total, total_pages: (total.to_f / per_page).ceil } }
      rescue ArgumentError
        render json: { error: { code: "invalid_parameters", message: "Invalid query parameters" } }, status: :bad_request
      end

      def show
        call = Call.find_by(call_id: params[:call_id])
        return render json: { error: { code: "not_found", message: "Call not found" } }, status: :not_found unless call

        render json: { data: serialize(call) }
      end

      private

      def positive_integer(name, default, maximum)
        value = request.query_parameters.fetch(name, default.to_s)
        raise ArgumentError unless value.is_a?(String) && value.match?(/\A[1-9]\d*\z/) && value.length <= 7
        number = value.to_i
        raise ArgumentError if number > maximum
        number
      end

      def timestamp(name)
        return unless request.query_parameters.key?(name)
        value = request.query_parameters[name]
        raise ArgumentError unless value.is_a?(String) && value.match?(/(?:Z|[+-]\d{2}:\d{2})\z/i)
        Time.iso8601(value).utc
      end

      def serialize(call)
        { call_id: call.call_id, caller: call.caller, callee: call.callee,
          started_at: call.started_at.utc.iso8601(6), answered_at: call.answered_at&.utc&.iso8601(6),
          ended_at: call.ended_at.utc.iso8601(6), duration_seconds: call.duration_seconds,
          status: call.status, created_at: call.created_at.utc.iso8601(6), updated_at: call.updated_at.utc.iso8601(6) }
      end
    end
  end
end
