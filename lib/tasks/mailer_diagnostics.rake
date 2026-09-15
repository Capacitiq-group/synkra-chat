# Email delivery diagnostics - built 14 Sep 2026 to verify Resend (or
# any SMTP provider) is actually wired up end to end, since this was
# flagged as "genuinely unknown - never verified" in the original
# handover for this session. See config/initializers/mailer.rb: this
# app's mailer config is pure generic SMTP, provider-agnostic - Resend
# needs NO code changes, only the right env vars (see config_check
# below for exactly which ones, and their Resend-specific values).
namespace :mailer do
  desc 'Print the effective SMTP config (never the password) - use to confirm the server is actually pointed at Resend'
  task config_check: :environment do
    puts "delivery_method: #{ActionMailer::Base.delivery_method}"
    if ActionMailer::Base.delivery_method == :smtp
      settings = ActionMailer::Base.smtp_settings
      puts "address: #{settings[:address]}"
      puts "port: #{settings[:port]}"
      puts "authentication: #{settings[:authentication]}"
      puts "user_name: #{settings[:user_name].presence || '(blank)'}"
      puts "password: #{settings[:password].present? ? '(set, hidden)' : '(BLANK - nothing will send)'}"
      puts "enable_starttls_auto: #{settings[:enable_starttls_auto]}"
      puts ''
      if settings[:address] == 'smtp.resend.com'
        puts 'Pointed at Resend.'
      elsif settings[:address] == 'localhost'
        puts 'WARNING: still on the "localhost" default - SMTP_ADDRESS is not set at all.'
      else
        puts "Pointed at #{settings[:address]}, not Resend - if you expected Resend, SMTP_ADDRESS is wrong."
      end
    else
      puts "Not using SMTP at all (using #{ActionMailer::Base.delivery_method}) - Resend would need delivery_method to be :smtp, which only happens when SMTP_ADDRESS is set."
    end
    puts ''
    puts "default from: #{ActionMailer::Base.default[:from]}"
    puts '(Resend requires the domain in the "from" address to be verified in the Resend dashboard - an unverified domain will fail or get sandboxed even with correct SMTP credentials.)'
  end

  desc 'Send a real test email end to end: rake mailer:send_test[you@example.com]'
  task :send_test, [:to] => :environment do |_t, args|
    if args[:to].blank?
      puts 'Usage: rake mailer:send_test[you@example.com]'
      next
    end

    begin
      MailerDiagnosticsMailer.test_delivery(to: args[:to]).deliver_now
      puts "Sent (no exception raised) - check #{args[:to]}'s inbox (and spam folder) to confirm it actually arrived."
      puts 'A successful call here means SMTP auth and connection succeeded - it does NOT guarantee inbox placement (that depends on domain verification/SPF/DKIM in Resend, and recipient spam filtering).'
    rescue StandardError => e
      puts "FAILED: #{e.class}: #{e.message}"
      puts 'This means the SMTP transport itself rejected the send - check SMTP_ADDRESS/PORT/USERNAME/PASSWORD (rake mailer:config_check) and that the Resend API key is valid and not revoked.'
    end
  end
end
