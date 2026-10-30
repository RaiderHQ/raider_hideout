module Api
  module V1
    module Public
      class TestsController < BaseController
        def index
          render json: reader.test_cases(params[:project_slug], api_params)
        end

        def show
          render json: reader.test_case(params[:project_slug], params[:id])
        end
      end
    end
  end
end
