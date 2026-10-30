module Api
  module V1
    module Public
      class ErrorsController < BaseController
        def index
          render json: reader.error_groups(params[:project_slug], api_params)
        end

        def show
          render json: reader.error_group(params[:project_slug], params[:id])
        end
      end
    end
  end
end
