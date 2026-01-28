# frozen_string_literal: true

module IPBlacklist
  class IPHealthManager

    class << self

      # Handle when a blacklist is detected for this IP
      def handle_blacklist_detected(blacklist_record)
        ip_address = blacklist_record.ip_address
        domain = blacklist_record.destination_domain

        # Create or update exclusion
        exclusion = IPDomainExclusion.find_or_initialize_by(
          ip_address: ip_address,
          destination_domain: domain
        )

        if exclusion.new_record?
          exclusion.assign_attributes(
            excluded_at: Time.current,
            reason: "Blacklisted on #{blacklist_record.blacklist_source}",
            warmup_stage: 0,
            ip_blacklist_record: blacklist_record
          )
          exclusion.save!

          Rails.logger.warn "[IP HEALTH] IP #{ip_address.ipv4} blacklisted on #{blacklist_record.blacklist_source} for domain #{domain}"
        else
          # If already excluded, update reason to include new blacklist
          current_reason = exclusion.reason || ""
          new_source = blacklist_record.blacklist_source

          unless current_reason.include?(new_source)
            exclusion.update!(
              reason: "#{current_reason}; #{new_source}".strip.sub(/^;/, ""),
              warmup_stage: 0, # Reset to paused if it was warming up
              next_warmup_at: nil
            )
          end

          Rails.logger.warn "[IP HEALTH] Updated exclusion for IP #{ip_address.ipv4} on domain #{domain}, reset to stage 0"
        end

        # Log the pause action
        IPHealthAction.create!(
          ip_address: ip_address,
          action_type: IPHealthAction::PAUSE,
          destination_domain: domain,
          reason: "IP blacklisted on #{blacklist_record.blacklist_source}",
          previous_priority: ip_address.priority,
          new_priority: 0,
          user_id: nil, # nil = automated
          triggered_by_blacklist_id: blacklist_record.id
        )

        Rails.logger.warn "[IP HEALTH] Paused IP #{ip_address.ipv4} for domain #{domain} (blacklist: #{blacklist_record.blacklist_source})"

        # Send notification using Notifier
        notifier = IPBlacklist::Notifier.new
        action = IPHealthAction.where(ip_address: ip_address, triggered_by_blacklist_id: blacklist_record.id).last
        notifier.notify_blacklist_detected(ip_address, blacklist_record)
        notifier.notify_ip_paused(ip_address, domain, "Blacklisted on #{blacklist_record.blacklist_source}", action) if action

        # Check if we need to trigger rotation
        check_rotation_possibility(blacklist_record)
      end

      # Start warmup process after blacklist is resolved
      def start_warmup(ip_address, destination_domain)
        exclusion = IPDomainExclusion.find_by(
          ip_address: ip_address,
          destination_domain: destination_domain
        )

        unless exclusion
          Rails.logger.error "[WARMUP] Exclusion not found for IP #{ip_address.ipv4} and domain #{destination_domain}"
          return
        end

        # Advance to stage 1 (priority 20) for 2 days
        exclusion.advance_warmup_stage!

        Rails.logger.info "[WARMUP] Starting warmup for IP #{ip_address.ipv4} on domain #{destination_domain} - Stage 1 (Priority 20)"
      end

      # Manually unpause an IP for a domain (admin override)
      def unpause_for_domain(ip_address, destination_domain, user: nil)
        exclusion = IPDomainExclusion.find_by(
          ip_address: ip_address,
          destination_domain: destination_domain
        )

        unless exclusion
          Rails.logger.info "[IP HEALTH] No exclusion found for IP #{ip_address.ipv4} and domain #{destination_domain}"
          return
        end

        exclusion.destroy!

        action = IPHealthAction.create!(
          ip_address: ip_address,
          action_type: IPHealthAction::UNPAUSE,
          destination_domain: destination_domain,
          reason: "Manual unpause by admin: #{user}",
          previous_priority: exclusion.current_priority,
          new_priority: ip_address.priority,
          user_id: nil # TODO: Look up user by email if needed
        )

        Rails.logger.info "[IP HEALTH] Manual unpause for IP #{ip_address.ipv4} on domain #{destination_domain} by #{user}"

        # Send notification
        notifier = IPBlacklist::Notifier.new
        notifier.notify_ip_resumed(ip_address, destination_domain, action)
      end

      # Manually pause an IP for a domain (admin action)
      def pause_for_domain(ip_address, destination_domain, reason: nil, user: nil)
        exclusion = IPDomainExclusion.find_or_initialize_by(
          ip_address: ip_address,
          destination_domain: destination_domain
        )

        if exclusion.new_record?
          exclusion.assign_attributes(
            excluded_at: Time.current,
            reason: reason || "Manual pause by admin",
            warmup_stage: 0
          )
          exclusion.save!
        else
          # Update existing exclusion
          exclusion.update!(
            warmup_stage: 0,
            reason: reason || "Manual pause by admin",
            next_warmup_at: nil
          )
        end

        action = IPHealthAction.create!(
          ip_address: ip_address,
          action_type: IPHealthAction::PAUSE,
          destination_domain: destination_domain,
          reason: "Manual pause by #{user}: #{reason || 'No reason provided'}",
          previous_priority: ip_address.priority,
          new_priority: 0,
          user_id: nil # TODO: Look up user by email if needed
        )

        Rails.logger.info "[IP HEALTH] Manual pause for IP #{ip_address.ipv4} on domain #{destination_domain} by #{user}"

        # Send notification
        notifier = IPBlacklist::Notifier.new
        notifier.notify_ip_paused(ip_address, destination_domain, reason || "Manual pause by admin", action)
      end

      private

      # Check if we have other healthy IPs available and log rotation info
      def check_rotation_possibility(blacklist_record)
        ip_address = blacklist_record.ip_address
        destination_domain = blacklist_record.destination_domain
        pool = ip_address.ip_pool

        healthy_ips = pool.ip_addresses
                          .where.not(id: ip_address.id)
                          .healthy_for_domain(destination_domain)

        if healthy_ips.empty?
          Rails.logger.error "[CRITICAL] No healthy IPs available in pool #{pool.name} for domain #{destination_domain}"
          log_notification("no_healthy_ips_critical", "CRITICAL: No healthy IPs in pool #{pool.name} for domain #{destination_domain}")
        else
          Rails.logger.info "[IP HEALTH] Found #{healthy_ips.count} healthy IP(s) available for rotation in pool #{pool.name} for domain #{destination_domain}"
          log_notification("rotation_available", "#{healthy_ips.count} healthy IPs available - recommend rotating traffic away from #{ip_address.ipv4}")
        end
      end

      # Send notification (replaced with proper Notifier implementation)
      def log_notification(type, message)
        Rails.logger.info "[NOTIFICATION] Type: #{type}, Message: #{message}"
        # Legacy method - notifications now handled by IPBlacklist::Notifier
      end

    end

  end
end
