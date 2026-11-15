# frozen_string_literal: true

require "ipaddr"

module Nero
  # An IPAddr from an address or a CIDR range.
  #
  #   admin: !ip 10.0.0.1
  #   office: !ip 192.168.0.0/24
  #   admin_ip: !ip [!env [ADMIN_IP, 127.0.0.1]]  # a sequence of one, to nest a tag
  #   proxies:                                   # a list: one !ip per item
  #     - !ip 173.245.48.0/20
  #     - !ip 2400:cb00::/32
  #
  # IPAddr#include? tells whether an address is in a range:
  #   config["office"].include?(request.remote_ip)
  class IpTag < BaseTag
    def resolve(args, context:)
      unless args.is_a?(Array) && args.size == 1 && args.first.is_a?(String)
        context.add_error("!ip expects one address or CIDR range, got #{args.inspect} " \
          "(for several, use a list with one !ip per item)")
        return
      end

      IPAddr.new(args.first)
    rescue IPAddr::Error
      context.add_error("!ip #{args.first.inspect} is not a valid IP address or CIDR range")
      nil
    end
  end
end
