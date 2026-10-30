module Api
  module V1
    module Public
      class ProjectsController < BaseController
        def index
          render json: reader.projects(api_params)
        end

        def show
          render json: reader.project(params[:project_slug])
        end
      end
    end
  end
end
