# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'MTA-STS Policy File Check' do
  let(:organization) { create(:organization) }
  let(:domain) { create(:domain, owner: organization, name: 'example.com', verified_at: Time.now) }

  describe '#check_mta_sts_policy_file' do
    before do
      domain.update(
        mta_sts_enabled: true,
        mta_sts_mode: 'enforce',
        mta_sts_max_age: 604800
      )
    end

    context 'when policy file is accessible and valid' do
      before do
        stub_request(:get, "https://mta-sts.example.com/.well-known/mta-sts.txt")
          .to_return(
            status: 200,
            body: "version: STSv1\nmode: enforce\nmx: *.mx.example.com\nmax_age: 604800\n"
          )
      end

      it 'returns success' do
        result = domain.check_mta_sts_policy_file
        expect(result[:success]).to be true
      end
    end

    context 'when policy file returns 404' do
      before do
        stub_request(:get, "https://mta-sts.example.com/.well-known/mta-sts.txt")
          .to_return(status: 404)
      end

      it 'returns error with status code' do
        result = domain.check_mta_sts_policy_file
        expect(result[:success]).to be false
        expect(result[:error]).to include('HTTP 404')
      end
    end

    context 'when policy file has invalid content' do
      before do
        stub_request(:get, "https://mta-sts.example.com/.well-known/mta-sts.txt")
          .to_return(
            status: 200,
            body: "invalid policy content"
          )
      end

      it 'returns error about missing version' do
        result = domain.check_mta_sts_policy_file
        expect(result[:success]).to be false
        expect(result[:error]).to include('version: STSv1')
      end
    end

    context 'when SSL certificate is invalid' do
      before do
        stub_request(:get, "https://mta-sts.example.com/.well-known/mta-sts.txt")
          .to_raise(OpenSSL::SSL::SSLError.new('certificate verify failed'))
      end

      it 'returns SSL error' do
        result = domain.check_mta_sts_policy_file
        expect(result[:success]).to be false
        expect(result[:error]).to include('SSL certificate error')
      end
    end

    context 'when connection times out' do
      before do
        stub_request(:get, "https://mta-sts.example.com/.well-known/mta-sts.txt")
          .to_timeout
      end

      it 'returns timeout error' do
        result = domain.check_mta_sts_policy_file
        expect(result[:success]).to be false
        expect(result[:error]).to include('Timeout')
      end
    end
  end

  describe '#check_mta_sts_record' do
    before do
      domain.update(
        mta_sts_enabled: true,
        mta_sts_mode: 'enforce',
        mta_sts_max_age: 604800
      )

      allow(domain).to receive(:resolver).and_return(double('resolver'))
    end

    context 'when DNS and HTTPS are both valid' do
      before do
        allow(domain.resolver).to receive(:txt)
          .with(domain.mta_sts_record_name)
          .and_return(['v=STSv1; id=abc123;'])

        stub_request(:get, "https://mta-sts.example.com/.well-known/mta-sts.txt")
          .to_return(
            status: 200,
            body: "version: STSv1\nmode: enforce\nmx: *.mx.example.com\nmax_age: 604800\n"
          )
      end

      it 'sets status to OK' do
        domain.check_mta_sts_record
        expect(domain.mta_sts_status).to eq('OK')
        expect(domain.mta_sts_error).to be_nil
      end
    end

    context 'when DNS is valid but HTTPS fails' do
      before do
        allow(domain.resolver).to receive(:txt)
          .with(domain.mta_sts_record_name)
          .and_return(['v=STSv1; id=abc123;'])

        stub_request(:get, "https://mta-sts.example.com/.well-known/mta-sts.txt")
          .to_return(status: 404)
      end

      it 'sets status to Invalid with HTTPS error' do
        domain.check_mta_sts_record
        expect(domain.mta_sts_status).to eq('Invalid')
        expect(domain.mta_sts_error).to include('HTTP 404')
      end
    end
  end
end

