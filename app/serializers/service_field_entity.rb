# frozen_string_literal: true

class ServiceFieldEntity < Grape::Entity
  include RequestAwareEntity

  expose :type, :name, :title, :placeholder, :required, :choices, :help

  expose :value do |field|
    value = service.public_send(field[:name]) # rubocop:disable GitlabSecurity/PublicSend

    if field[:type] == 'password' && value.present?
      'true'
    else
      value
    end
  end

  private

  def service
    request.service
  end
end
