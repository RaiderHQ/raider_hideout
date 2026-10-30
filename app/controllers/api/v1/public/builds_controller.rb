module Api
  module V1
    module Public
      class BuildsController < BaseController
        def index
          render json: reader.builds(params[:project_slug], api_params)
        end

        def show
          render json: reader.build(params[:project_slug], params[:id], api_params)
        end
      end
    end
  end
end
