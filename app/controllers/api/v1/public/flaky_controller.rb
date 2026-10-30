module Api
  module V1
    module Public
      class FlakyController < BaseController
        def index
          render json: reader.flaky_tests(params[:project_slug], api_params)
        end
      end
    end
  end
end
