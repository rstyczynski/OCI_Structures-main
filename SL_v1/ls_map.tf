
variable "sl_map" {

  # TODO remove map with "rules". Sufficient here is just map of lists of objects
  default = {
      "demo1" = {
      rules = [
        {
          protocol    = "tcp/22",
          dst = "all",
          description = "ssh for all!"
        },
        {
          protocol    = "tcp/80-90",
          dst = "0.0.0.0/0"
          stateless   = true,
        },
        {
          protocol    = "tcp/:1521-1523",
          dst = "0.0.0.0/0"
        },
        {
          protocol    = "TcP/22:",
          src = "0.0.0.0/0"
        },
        {
          protocol    = "TcP/21-22:1521-1523",
          src = "0.0.0.0/0"
        }
      ]
      },
      "demo2" = {
        rules = [
          {
            protocol    = "icmp/3.4",
            dst = "0.0.0.0/0"
          },
          {
            protocol = "icmp/8",
            src   = "0.0.0.0/0"
          }
        ]
      },
      "demo3" = {
        rules = [
          {
            protocol    = "icmp/3.4",
            dst = "0.0.0.0/0;1.2.3.4/5"
          },
          {
            protocol = "icmp/8",
            src   = "8.9.10.11/12;0.0.0.0/0"
          },
          {
            protocol = "icmp/8",
            src   = "_test.label_multiple"
          }
        ]
      }
    }

  type = map(object({
          rules = list(object(
            {
              protocol    = string
              src      = optional(string)
              dst = optional(string)
              description = optional(string)
              stateless   = optional(bool)
            }))
        }))
  
}

# select data source to enable sl_lex format
variable data_format {
  type = string
  default = "sl_lang" # sl_lex to use lex format; ls_map otherwise.
}

# select key for output ingress and egress lists
variable sl_key {
  type = string
  default = "demo1"
}

#
# known networks map. Register here CIDR labels
#
variable cidrs {
    type = map(string)
    default = {
        "on_premises" = "192.0.0.0/8"
    }
}

locals {
    global_cidrs = {
        "all" = "0.0.0.0/0",
        "all_services" = "all_services"
    }

    test_cidrs = {
      "_test.label_multiple" = "1.2.3.4/5;6.7.8.9/10"
    }

    # var.cidrs is at the end to be able to overwrite default values 
    cidrs = merge(local.global_cidrs, local.test_cidrs, var.cidrs)
}   

output cidrs {
  value = local.cidrs
}

###
### Processing
###

#
# switch data source to enable sl_lex format
#
locals {
  sl_map = var.data_format == "sl_map" ? var.sl_map : var.data_format == "sl_lex" ? local.sl_lex_map : var.data_format == "sl_lang" ? local.sl_lang_map : null
}

#
# render CIDR from labels
# 
output sl_cidr {
  value = local.sl_cidr
}
# output sl_cidr_step3 {
#   value = local.sl_cidr_step3
# }
locals {
  sl_cidr = local.sl_cidr_step3

  # substitute labels
  sl_cidr_step1 = {
    for key, value in local.sl_map : 
    key => {
      rules = [
        for ndx, rule in value.rules :
        {
          protocol    = can(rule.protocol) ? rule.protocol : null
          src         = rule.src == null ? null : can(regex(local.regexp_cidr, rule.src)) ? rule.src : can(local.cidrs[rule.src]) ? local.cidrs[rule.src] : "label not in local.cidrs"
          dst         = rule.dst == null ? null : can(regex(local.regexp_cidr, rule.dst)) ? rule.dst : can(local.cidrs[rule.dst]) ? local.cidrs[rule.dst] : "label not in local.cidrs"
          description = can(rule.description) ? rule.description : null
          stateless   = can(rule.stateless) ? rule.stateless : null
        }
      ]
    }
  }

  # extend multiple dst CIDRs
  sl_cidr_step2 = {
    for key, value in local.sl_cidr_step1 : 
    key => {
      rules = flatten([
        for ndx, rule in value.rules : [
          for dst in split(";", can(rule.dst) ? rule.dst == null ? "" : rule.dst : null): {
              protocol    = can(rule.protocol) ? rule.protocol : null
              src         = can(rule.src) ? rule.src : null
              dst         = dst == "" ? null : dst
              description = can(rule.description) ? rule.description : null
              stateless   = can(rule.stateless) ? rule.stateless : null
            }
        ]
      ])
    }
  }

  # extend multiple src CIDRs
  sl_cidr_step3 = {
    for key, value in local.sl_cidr_step2 : 
    key => {
      rules = flatten([
        for ndx, rule in value.rules : [
          for src in split(";", can(rule.src) ? rule.src == null ? "" : rule.src : ""): {
              protocol    = can(rule.protocol) ? rule.protocol : null
              src         = src == "" ? null : src
              dst         = can(rule.dst) ? rule.dst : null
              description = can(rule.description) ? rule.description : null
              stateless   = can(rule.stateless) ? rule.stateless : null
            }
        ]
      ])
    }
  }
}

# add index variable to keep order of records
# it's needed as processing is implemented for subsets of the list
# having index field, it's possible to keep original order in final list
locals {
  sl_indexed = {
    for key, value in local.sl_cidr : 
    key => {
      rules = [
        for ndx, rule in value.rules :
        {
          _position   = ndx
          protocol    = rule.protocol
          src         = rule.src
          dst         = rule.dst
          description = rule.description 
          stateless   = rule.stateless
        }
      ]
    }
  }
}
# output "sl_indexed" {
#   value = local.sl_indexed
# }

# # part of the input list is processed for generic patterns
# # /22:
# # /22-23:
# # /22-23:80
# # /22-23:80-81
locals {
  regexp_full = format("^%s\\s*%s", local.regexp_ip_ports_full, local.regexp_eol)

  sl_src_dst = {
    for key, value in local.sl_indexed :
      key => {
        for rule in value.rules :
          rule._position => {
            _position = tonumber(rule._position)

            src_string = rule.protocol
            src_port_min  = regex(local.regexp_full, rule.protocol)[1]
            src_port_max  = regex(local.regexp_full, rule.protocol)[2] != "" ? regex(local.regexp_full, rule.protocol)[2] : regex(local.regexp_full, rule.protocol)[1]

            dst_port_min = regex(local.regexp_full, rule.protocol)[3]
            dst_port_max = regex(local.regexp_full, rule.protocol)[4] != "" ? regex(local.regexp_full, rule.protocol)[4] : regex(local.regexp_full, rule.protocol)[3]

            icmp_type = null
            icmp_code = null

            protocol = lower(split("/", rule.protocol)[0])

            src      = rule.src
            #TODO Detect NETWORK_SECURITY_GROUP by OCID prefix
            src_type = rule.src == null ? null : can(regex(local.regexp_cidr, rule.src)) ? "CIDR_BLOCK" : "SERVICE_CIDR_BLOCK"

            dst      = rule.dst
            #TODO Detect NETWORK_SECURITY_GROUP by OCID prefix
            dst_type = rule.dst == null ? null : can(regex(local.regexp_cidr, rule.dst)) ? "CIDR_BLOCK" : "SERVICE_CIDR_BLOCK"

            stateless   = rule.stateless
            description = rule.description

            type = "sl_src_dst"
        } if can(regex(local.regexp_full, rule.protocol)) 
    }
  }
}
# output "sl_src_dst" {
#   value = local.sl_src_dst
# }

# # another part of the input list is processed for default patterns
# # /80
# # /80-81
locals {
  regexp_dst = format("^%s\\s*%s", local.regexp_ip_ports_dst, local.regexp_eol)

  sl_dst_only = {
    for key, value in local.sl_indexed : 
      key => { 
        for rule in value.rules :
          rule._position => {
            _position = tonumber(rule._position)

            src_string = rule.protocol
            src_port_min  = null
            src_port_max  = null

            dst_port_min = regex(local.regexp_dst, rule.protocol)[1]
            dst_port_max = regex(local.regexp_dst, rule.protocol)[2] != "" ? regex(local.regexp_dst, rule.protocol)[2] : regex(local.regexp_dst, rule.protocol)[1]

            icmp_type = null
            icmp_code = null

            protocol = lower(split("/", rule.protocol)[0])

            src      = rule.src
            #TODO Detect NETWORK_SECURITY_GROUP by OCID prefix
            src_type = rule.src == null ? null : can(regex(local.regexp_cidr, rule.src)) ? "CIDR_BLOCK" : "SERVICE_CIDR_BLOCK"

            dst      = rule.dst
            #TODO Detect NETWORK_SECURITY_GROUP by OCID prefix
            dst_type = rule.dst == null ? null : can(regex(local.regexp_cidr, rule.dst)) ? "CIDR_BLOCK" : "SERVICE_CIDR_BLOCK"

            stateless   = rule.stateless
            description = rule.description

            type = "sl_dst_only" 
          } if can(regex(local.regexp_dst, rule.protocol))
      }
  }
}
# output "sl_dst_only" {
#   value = local.sl_dst_only
# }

# process icmp
# icmp/8
# icmp/8.1
locals {
  regexp_icmp = format("^%s\\s*%s", local.regexp_icmp_tc, local.regexp_eol)

  sl_icmp = {
    for key, value in local.sl_indexed : 
      key => {
      for rule in value.rules :
        rule._position => {
          _position = tonumber(rule._position)

          src_string = rule.protocol

          src_port_min = null
          src_port_max = null

          dst_port_min = null
          dst_port_max = null

          icmp_type = regex(local.regexp_icmp, rule.protocol)[0]
          icmp_code = regex(local.regexp_icmp, rule.protocol)[1] != "" ? regex(local.regexp_icmp, rule.protocol)[1] : null

          protocol = lower(split("/", rule.protocol)[0])

          src      = rule.src
          src_type = rule.src == null ? null : can(regex(local.regexp_cidr, rule.src)) ? "CIDR_BLOCK" : "SERVICE_CIDR_BLOCK"

          dst      = rule.dst
          dst_type = rule.dst == null ? null : can(regex(local.regexp_cidr, rule.dst)) ? "CIDR_BLOCK" : "SERVICE_CIDR_BLOCK"

          stateless   = rule.stateless
          description = rule.description

          type          = "sl_icmp"
       } if can(regex(local.regexp_icmp, rule.protocol))
      }
    }
  }
output "sl_icmp" {
  value = local.sl_icmp
}

#
# mark unrecognized records as errors
#
locals {
  sl_error = {
    for key, value in local.sl_indexed : 
      key => {
      for rule in value.rules :
        rule._position => {
            _position = tonumber(rule._position)
            src_string = rule.protocol

            src_port_min = 0
            src_port_max = null

            dst_port_min = 0
            dst_port_max = null

            icmp_type = null
            icmp_code = null
            
            protocol = "ERROR"

            src      = null
            src_type = null
            
            dst      = null
            dst_type = null

            stateless   = null
            description = null

            type         = "sl_unrecognized"
          } if ! can(regex(local.regexp_full, rule.protocol)) && ! can(regex(local.regexp_dst, rule.protocol)) && ! can(regex(local.regexp_icmp, rule.protocol))
        }
      }
    }
output "sl_error" {
  value = local.sl_error
}

locals {
  # generate sorted positions for each key
  positions_per_key = {
    for key, value in local.sl_indexed : 
      key =>
      sort(formatlist("%010d", [for rule in value.rules : rule._position]))
  }
}
# output "positions_per_key" {
#   value = local.positions_per_key
# }

# combine all partially processed lists to the final one
# keep original order
locals {
  sl_processed = {
    for key, value in local.sl_indexed : 
      key => {
        rules = [
          for position in local.positions_per_key[key]:
            can(local.sl_src_dst[key][tonumber(position)])
              ? local.sl_src_dst[key][tonumber(position)]
              : can(local.sl_dst_only[key][tonumber(position)])
                  ? local.sl_dst_only[key][tonumber(position)]
                  : can(local.sl_icmp[key][tonumber(position)])
                      ? local.sl_icmp[key][tonumber(position)]
                      : can(local.sl_error[key][tonumber(position)])
                          ? local.sl_error[key][tonumber(position)]
                          : local.sl_critical_error["error"]
        ]
      }
    }
}
# output "sl_processed" {
#   value = local.sl_processed
# }


