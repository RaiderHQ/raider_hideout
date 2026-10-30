module Api
  module V1
    module Public
      class QuarantinesController < BaseController
        def index
          render json: reader.quarantines(params[:project_slug], api_params)
        end
      end
    end
  end
end
