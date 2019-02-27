# frozen_string_literal: true

require 'digest'
require "#{APP_ROOT}/lib/active_storage/openstack/client"
require "#{APP_ROOT}/lib/active_storage/openstack/client/storage"

describe ActiveStorage::Openstack::Client::Storage do
  cassette_path = 'lib/active_storage/openstack/storage'

  subject(:storage) do
    described_class.new authenticator: authenticator,
                        container: container,
                        region: region
  end

  let(:username) { Rails.application.credentials.openstack.fetch(:username) }
  let(:password) { Rails.application.credentials.openstack.fetch(:api_key) }
  let(:authenticator) do
    ActiveStorage::Openstack::Client::Authenticator.new username: username,
                                                        password: password
  end
  let(:container) { Rails.application.config.x.openstack.fetch(:container) }
  let(:region) { Rails.application.config.x.openstack.fetch(:region) }

  before do
    VCR.use_cassette(
      'lib/active_storage/openstack/authenticator/authenticate'
    ) do
      authenticator&.authenticate
    end
  end

  it { is_expected.to be_valid }

  context 'without authenticator' do
    let(:authenticator) { nil }

    it { is_expected.to be_invalid }
  end

  context 'without container' do
    let(:container) { nil }

    it { is_expected.to be_invalid }
  end

  context 'without region' do
    let(:region) { nil }

    it { is_expected.to be_invalid }
  end

  describe '#uri' do
    subject(:uri) { storage.uri }

    it { is_expected.to be_an_instance_of(URI::HTTPS) }
    it { expect(uri.to_s).to include(storage.region.downcase) }
    it { expect(uri.to_s).to include(storage.container) }
  end

  describe '#get_object', vcr: {
    cassette_name: "#{cassette_path}/get_object"
  } do
    subject(:get_object) { storage.get_object(object_path) }

    let(:filename) { 'test.jpg' }
    let(:object_path) { "/fixtures/files/images/#{filename}" }

    it 'returns Success code' do
      expect(Integer(get_object.code)).to equal(200) # Success
    end
  end

  describe '#put_object' do
    subject(:put_object) do
      storage.put_object(file, object_path, checksum: checksum)
    end

    let(:filename) { 'test.jpg' }
    let(:object_path) { "/fixtures/files/images/#{filename}" }
    let(:file) { file_fixture("images/#{filename}") }
    let(:checksum) { Digest::MD5.file(file).hexdigest }

    it 'returns Created code', vcr: {
      cassette_name: "#{cassette_path}/put_object"
    } do
      expect(Integer(put_object.code)).to equal(201) # Created
    end

    context 'when checksum fails', vcr: {
      cassette_name: "#{cassette_path}/put_object-bad_checksum"
    } do
      let(:checksum) { 'bad_checksum' }

      it 'returns Unprocessable Entity code' do
        expect(Integer(put_object.code)).to equal(422) # Unprocessable Entity
      end
    end
  end

  describe '#delete_object', vcr: {
    cassette_name: "#{cassette_path}/delete_object"
  } do
    subject(:delete_object) { storage.delete_object(object_path) }

    let(:filename) { 'test.jpg' }
    let(:object_path) { "/fixtures/files/images/#{filename}" }

    it 'returns No Content code' do
      expect(Integer(delete_object.code)).to equal(204) # No content
    end
  end

  describe '#show_object_metadata', vcr: {
    cassette_name: "#{cassette_path}/show_object_metadata"
  } do
    subject(:show_object_metadata) do
      storage.show_object_metadata(object_path)
    end

    let(:filename) { 'test.jpg' }
    let(:object_path) { "/fixtures/files/images/#{filename}" }

    it 'returns Success code' do
      expect(Integer(show_object_metadata.code)).to equal(200) # Success
    end

    context 'when file does not exist', vcr: {
      cassette_name: "#{cassette_path}/show_object_metadata-not_found"
    } do
      let(:object_path) { '/unknown_file.jpg' }

      it 'returns Not found code' do
        expect(Integer(show_object_metadata.code)).to equal(404) # Not found
      end
    end
  end
end