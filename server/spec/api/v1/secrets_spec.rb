require_relative '../../spec_helper'



describe 'secrets' do

  let(:request_headers) do
    { 'HTTP_AUTHORIZATION' => "Bearer #{valid_token.token}" }
  end

  let(:grid) do
    Grid.create!(name: 'big-one')
  end

  let(:another_grid) do
    Grid.create!(name: 'another-one')
  end

  let(:david) do
    user = User.create!(email: 'david@domain.com', external_id: '123456')
    grid.users << user
    user
  end

  let(:valid_token) do
    AccessToken.create!(user: david, scopes: ['user'])
  end

  describe 'POST /v1/grids/:grid/secrets' do
    it 'saves a new secret' do
      data = {name: 'PASSWD', value: 'secretzz'}
      expect {
        post "/v1/grids/#{grid.to_path}/secrets", data.to_json, request_headers
        expect(response.status).to eq(201)
      }.to change{ grid.grid_secrets.count }.by(1)
    end

    it 'returns error on duplicate name' do
      grid.grid_secrets.create!(name: 'PASSWD', value: 'aaaa')
      data = {name: 'PASSWD', value: 'secretzz'}
      post "/v1/grids/#{grid.to_path}/secrets", data.to_json, request_headers
      expect(response.status).to eq(422)
    end

    it 'returns error if user has no access to grid' do
      data = {name: 'PASSWD', value: 'secretzz'}
      post "/v1/grids/#{another_grid.to_path}/secrets", data.to_json, request_headers
      expect(response.status).to eq(404)
    end
  end

  describe 'GET /v1/grids/:grid/secrets' do
    it 'returns empty array if no secrets' do
      get "/v1/grids/#{grid.to_path}/secrets", nil, request_headers
      expect(response.status).to eq(200)
      expect(json_response['secrets']).to eq([])
    end

    it 'returns secrets array' do
      grid.grid_secrets.create(name: 'foo', value: 'supersecret')
      get "/v1/grids/#{grid.to_path}/secrets", nil, request_headers
      expect(response.status).to eq(200)
      expect(json_response['secrets'].size).to eq(1)
      secret = json_response['secrets'][0]
      expect(secret.keys.sort).to eq(%w(id name created_at).sort)
    end
  end

  describe 'GET /v1/secrets/:name' do
    it 'returns secret with value' do
      secret = grid.grid_secrets.create(name: 'foo', value: 'supersecret')
      get "/v1/secrets/#{secret.to_path}", nil, request_headers
      expect(response.status).to eq(200)
      expect(json_response['value']).to eq(secret.value)
    end

    it 'creates an audit entry' do
      secret = grid.grid_secrets.create(name: 'foo', value: 'supersecret')
      expect {
        get "/v1/secrets/#{secret.to_path}", nil, request_headers
      }.to change{ grid.audit_logs.count }.by(1)
    end

    it 'returns error if user has no access to grid' do
      secret = another_grid.grid_secrets.create(name: 'foo', value: 'supersecret')
      get "/v1/secrets/#{secret.to_path}", nil, request_headers
      expect(response.status).to eq(403)
    end
  end

  describe 'DELETE /v1/secrets/:name' do
    it 'removes secret' do
      secret = grid.grid_secrets.create(name: 'foo', value: 'supersecret')
      expect {
        delete "/v1/secrets/#{secret.to_path}", nil, request_headers
        expect(response.status).to eq(200)
      }.to change{ grid.grid_secrets.count }.by(-1)
    end

    it 'creates an audit entry' do
      secret = grid.grid_secrets.create(name: 'foo', value: 'supersecret')
      expect {
        delete "/v1/secrets/#{secret.to_path}", nil, request_headers
      }.to change{ grid.audit_logs.count }.by(1)
    end

    it 'returns error if user has no access to grid' do
      secret = another_grid.grid_secrets.create(name: 'foo', value: 'supersecret')
      delete "/v1/secrets/#{secret.to_path}", nil, request_headers
      expect(response.status).to eq(403)
    end
  end
end

