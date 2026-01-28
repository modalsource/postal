# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "MTA-STS Policy", type: :request do
  describe "GET /.well-known/mta-sts.txt" do
    let(:organization) { create(:organization) }

    context "when domain has MTA-STS enabled" do
      let!(:domain) do
        create(:domain,
               owner: organization,
               name: 'example.com',
               verified_at: Time.now,
               mta_sts_enabled: true,
               mta_sts_mode: 'enforce',
               mta_sts_max_age: 86400)
      end

      it "returns the MTA-STS policy" do
        get "/.well-known/mta-sts.txt", headers: { 'Host' => 'mta-sts.example.com' }

        expect(response).to have_http_status(:ok)
        expect(response.content_type).to eq('text/plain; charset=utf-8')
        expect(response.body).to include('version: STSv1')
        expect(response.body).to include('mode: enforce')
        expect(response.body).to include('max_age: 86400')
      end

      it "sets the correct cache control header" do
        get "/.well-known/mta-sts.txt", headers: { 'Host' => 'mta-sts.example.com' }

        expect(response.headers['Cache-Control']).to include('max-age=86400')
      end
    end

    context "when domain has MTA-STS enabled with custom MX patterns" do
      let!(:domain) do
        create(:domain,
               owner: organization,
               name: 'example.com',
               verified_at: Time.now,
               mta_sts_enabled: true,
               mta_sts_mode: 'testing',
               mta_sts_max_age: 604800,
               mta_sts_mx_patterns: "*.mx1.example.com\n*.mx2.example.com")
      end

      it "includes custom MX patterns in the policy" do
        get "/.well-known/mta-sts.txt", headers: { 'Host' => 'mta-sts.example.com' }

        expect(response).to have_http_status(:ok)
        expect(response.body).to include('mx: *.mx1.example.com')
        expect(response.body).to include('mx: *.mx2.example.com')
        expect(response.body).to include('mode: testing')
      end
    end

    context "when domain is not verified" do
      let!(:domain) do
        create(:domain,
               owner: organization,
               name: 'example.com',
               verified_at: nil,
               mta_sts_enabled: true,
               mta_sts_mode: 'enforce',
               mta_sts_max_age: 86400)
      end

      it "returns 404 not found" do
        get "/.well-known/mta-sts.txt", headers: { 'Host' => 'mta-sts.example.com' }

        expect(response).to have_http_status(:not_found)
        expect(response.body).to include('MTA-STS policy not found')
      end
    end

    context "when domain has MTA-STS disabled" do
      let!(:domain) do
        create(:domain,
               owner: organization,
               name: 'example.com',
               verified_at: Time.now,
               mta_sts_enabled: false)
      end

      it "returns 404 not found" do
        get "/.well-known/mta-sts.txt", headers: { 'Host' => 'mta-sts.example.com' }

        expect(response).to have_http_status(:not_found)
        expect(response.body).to include('MTA-STS policy not found')
      end
    end

    context "when domain does not exist" do
      it "returns 404 not found" do
        get "/.well-known/mta-sts.txt", headers: { 'Host' => 'mta-sts.nonexistent.com' }

        expect(response).to have_http_status(:not_found)
        expect(response.body).to include('MTA-STS policy not found')
      end
    end

    context "when host is the main domain without mta-sts prefix" do
      let!(:domain) do
        create(:domain,
               owner: organization,
               name: 'example.com',
               verified_at: Time.now,
               mta_sts_enabled: true,
               mta_sts_mode: 'enforce',
               mta_sts_max_age: 86400)
      end

      it "returns the MTA-STS policy" do
        get "/.well-known/mta-sts.txt", headers: { 'Host' => 'example.com' }

        expect(response).to have_http_status(:ok)
        expect(response.content_type).to eq('text/plain; charset=utf-8')
        expect(response.body).to include('version: STSv1')
      end
    end

    context "when domain name is case-insensitive" do
      let!(:domain) do
        create(:domain,
               owner: organization,
               name: 'example.com',
               verified_at: Time.now,
               mta_sts_enabled: true,
               mta_sts_mode: 'enforce',
               mta_sts_max_age: 86400)
      end

      it "returns the MTA-STS policy" do
        get "/.well-known/mta-sts.txt", headers: { 'Host' => 'mta-sts.EXAMPLE.COM' }

        expect(response).to have_http_status(:ok)
        expect(response.body).to include('version: STSv1')
      end
    end
  end
end

