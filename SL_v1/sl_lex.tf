variable "sl_lex" {
  type = map(list(string))

  default = {
      "demo1" = [
        "TcP/21-22:1521-1523 >> 0.0.0.0/0 /* DB for some of you */",
        "0.0.0.0/0      >> uDP/20000-30000:80-90 /* HTTP over UDP for some of you */",
        "tcp/:1521-1523 > 0.0.0.0/0",
        "0.0.0.0/0      >> uDP/22-23 /* xx */",
        "tcp/22         >> 0.0.0.0/0 /* ssh for all! */",
        "0.0.0.0/0      > TcP/21-22:1521-1523 /* DB for everyone */" ,
        "tcp/80-90      >  0.0.0.0/0",
        "0.0.0.0/0      >> uDP/222-223",
      ],
      "demo2" = [
        "icmp/3.4       >> 0.0.0.0/0 /* icmp type 3, code 4 */",
        "0.0.0.0/0      >> icmp/8",
        "0.0.0.0/0      >> icmp/1. /* icmp type 1 */",
        "icmp/3.        > 0.0.0.0/0",
        "0.0.0.0/0      > icmp/8.1"        
        ]
      }
}
// output sl_lex {
//     value = var.sl_lex
// }

#  pattern to decode lexical rule
locals {
    regexp_egress = "(?i)(tcp|udp)\\/([0-9]*)-?([0-9]*):([0-9]*)-?([0-9]*)\\s*(>{1,2})\\s*([0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\/[0-9]{1,3})\\s*(?:\\/\\*\\s*)?(?:([\\w !]*))(?:\\*\\/)?" 
    regexp_ingress  = "([0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\/[0-9]{1,3})\\s*(>{1,2})\\s*(?i)(tcp|udp)\\/([0-9]*)-?([0-9]*):([0-9]*)-?([0-9]*)\\s*(?:\\/\\*\\s*)?(?:([\\w !]*))(?:\\*\\/)?"
}

# patterns for special case of dst only
locals {
    regexp_egress_dst = "(?i)(tcp|udp)\\/([0-9]*)-?([0-9]*)\\s*(>{1,2})\\s*([0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\/[0-9]{1,3})\\s*(?:\\/\\*\\s*)?(?:([\\w !]*))(?:\\*\\/)?"
    // regexp_ingress_dst_cmt takes full syntaxt with comments
    // regexp_ingress_dst is ended by $
    // both are workaround for lack of knowlkedge how to forbid ':' character after ports.
    // w/o above ingress_dst regexp matches generic regexp_ingress
    regexp_ingress_dst_cmt = "([0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\/[0-9]{1,3})\\s*(>{1,2})\\s*(?i)(tcp|udp)\\/([0-9]*)-?([0-9]*)\\s*\\/\\*\\s*(?:([\\w !]*))\\*\\/"
    regexp_ingress_dst = "([0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\/[0-9]{1,3})\\s*(>{1,2})\\s*(?i)(tcp|udp)\\/([0-9]*)-?([0-9]*)$"
}

# patterns for icmp
locals {
    regexp_icmp_egress = "(?i)icmp\\/([0-9]*).?([0-9]*)\\s*(>{1,2})\\s*([0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\/[0-9]{1,3})\\s*$"
    regexp_icmp_egress_cmt = "(?i)icmp\\/([0-9]*).?([0-9]*)\\s*(>{1,2})\\s*([0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\/[0-9]{1,3})\\s*(?:\\/\\*\\s*)(?:([\\w !]*))(?:\\*\\/)"
    regexp_icmp_ingress = "([0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\/[0-9]{1,3})\\s*(>{1,2})\\s*(?i)icmp\\/([0-9]*).?([0-9]*)\\s*$"
    regexp_icmp_ingress_cmt = "([0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\/[0-9]{1,3})\\s*(>{1,2})\\s*(?i)icmp\\/([0-9]*).?([0-9]*)\\s*(?:\\/\\*\\s*)(?:([\\w !]*))(?:\\*\\/)"
}

# add index variable to keep order of records
# it's needed as processing is implemented for subsets of the list
# having index field, it's possible to keep oryginal order in final list
locals {
  sl_lex_indexed = {
    for key, value in var.sl_lex : 
    key => [
        for ndx, rule in value :
        {
            _position   = ndx
            rule = rule
        } 
        ] 
  } 
}
// output sl_lex_indexed {
//     value = local.sl_lex_indexed
// }

locals {
  sl_lex_egress_error = {
    "0" = {
            _position   = -1
            _format = "error"
            description = "Processing error."
            protocol = "error/0"
            source      = null
            destination = null
            stateless = null
        } 
    } 
} 

# process generic egress pattern
locals {
  sl_lex_egress = {
    for key, value in local.sl_lex_indexed : 
    key => {
        for record in value :
        record._position => {
            _position   = record._position
            _format     = "regexp_egress"

            # try egress generic
            protocol    = format("%s/%s-%s:%s-%s",
                regex(local.regexp_egress, record.rule)[0], # protocol
                regex(local.regexp_egress, record.rule)[1], # src_min
                regex(local.regexp_egress, record.rule)[2], # src_max
                regex(local.regexp_egress, record.rule)[3], # dst_min
                regex(local.regexp_egress, record.rule)[4]  # dst_max
            )
            source      = null
            destination = regex(local.regexp_egress, record.rule)[6]
            description = regex(local.regexp_egress, record.rule)[7]
            stateless   = regex(local.regexp_egress, record.rule)[5] == ">>" ? true : regex(local.regexp_egress, record.rule)[5] == ">" ? false : null
        } if can(regex(local.regexp_egress, record.rule))
    } 
  } 
}
// output sl_lex_egress {
//     value = local.sl_lex_egress
// }

# process generic ingress pattern
locals {
  sl_lex_ingress = {
    for key, value in local.sl_lex_indexed : 
    key => {
        for record in value :
        record._position => {
            _position   = record._position
            _format     = "regexp_ingress"

            # try egress generic
            protocol    = format("%s/%s-%s:%s-%s",
                regex(local.regexp_ingress, record.rule)[2], # protocol
                regex(local.regexp_ingress, record.rule)[3], # src_min
                regex(local.regexp_ingress, record.rule)[4], # src_max
                regex(local.regexp_ingress, record.rule)[5], # dst_min
                regex(local.regexp_ingress, record.rule)[6]  # dst_max
            )
            source = regex(local.regexp_ingress, record.rule)[0]
            destination = null
            description = regex(local.regexp_ingress, record.rule)[7]
            stateless   = regex(local.regexp_ingress, record.rule)[1] == ">>" ? true : regex(local.regexp_ingress, record.rule)[1] == ">" ? false : null
        } if can(regex(local.regexp_ingress, record.rule))
    } 
  } 
}
// output sl_lex_ingress {
//     value = local.sl_lex_ingress
// }

# process simplified egress pattern
locals {
  sl_lex_egress_dst = {
    for key, value in local.sl_lex_indexed : 
    key => {
        for record in value :
        record._position => {
            _position   = record._position
            _format     = "regexp_egress_dst"

            protocol    = format("%s/%s-%s",
                regex(local.regexp_egress_dst, record.rule)[0], # protocol
                regex(local.regexp_egress_dst, record.rule)[1], # dst_min
                regex(local.regexp_egress_dst, record.rule)[2]  # dst_max
            )
            source      = null
            destination = regex(local.regexp_egress_dst, record.rule)[4]
            description = regex(local.regexp_egress_dst, record.rule)[5]
            stateless   = regex(local.regexp_egress_dst, record.rule)[3] == ">>" ? true : regex(local.regexp_egress_dst, record.rule)[3] == ">" ? false : null
        } if can(regex(local.regexp_egress_dst, record.rule))
    } 
  } 
}
// output sl_lex_egress_dst {
//     value = local.sl_lex_egress_dst
// }

# process simplified ingress pattern w/o comment
locals {
  sl_lex_ingress_dst = {
    for key, value in local.sl_lex_indexed : 
    key => {
        for record in value :
        record._position => {
            _position   = record._position
            _format     = "regexp_ingress_dst"

            _source     = record.rule
            _regexp     = local.regexp_ingress_dst

            protocol    = format("%s/%s-%s",
                regex(local.regexp_ingress_dst, record.rule)[2], # protocol
                regex(local.regexp_ingress_dst, record.rule)[3], # dst_min
                regex(local.regexp_ingress_dst, record.rule)[4]  # dst_max
            )
            source = regex(local.regexp_ingress_dst, record.rule)[0]
            destination = null
            description = null
            stateless   = regex(local.regexp_ingress_dst, record.rule)[1] == ">>" ? true : regex(local.regexp_ingress_dst, record.rule)[1] == ">" ? false : null
        } if can(regex(local.regexp_ingress_dst, record.rule))
    } 
  } 
}
// output sl_lex_ingress_dst {
//     value = local.sl_lex_ingress_dst
// }

# process simplified ingress pattern
locals {
  sl_lex_ingress_dst_cmt = {
    for key, value in local.sl_lex_indexed : 
    key => {
        for record in value :
        record._position => {
            _position   = record._position
            _format     = "regexp_ingress_dst"

            _source     = record.rule
            _regexp     = local.regexp_ingress_dst_cmt

            protocol    = format("%s/%s-%s",
                regex(local.regexp_ingress_dst_cmt, record.rule)[2], # protocol
                regex(local.regexp_ingress_dst_cmt, record.rule)[3], # dst_min
                regex(local.regexp_ingress_dst_cmt, record.rule)[4]  # dst_max
            )
            source = regex(local.regexp_ingress_dst_cmt, record.rule)[0]
            destination = null
            description = regex(local.regexp_ingress_dst_cmt, record.rule)[5]
            stateless   = regex(local.regexp_ingress_dst_cmt, record.rule)[1] == ">>" ? true : regex(local.regexp_ingress_dst_cmt, record.rule)[1] == ">" ? false : null
        } if can(regex(local.regexp_ingress_dst_cmt, record.rule))
    }
  } 
}
// output sl_lex_ingress_dst_cmt {
//     value = local.sl_lex_ingress_dst_cmt
// }

# process simplified ingress icmp pattern with comment
locals {
  sl_lex_icmp_ingress_cmt = {
    for key, value in local.sl_lex_indexed : 
    key => {
        for record in value :
        record._position => {
            _position   = record._position
            _format     = "regexp_icmp_ingress_cmt"

            _source     = record.rule
            _regexp     = local.regexp_icmp_ingress_cmt

            protocol    = format("icmp/%s.%s",
                regex(local.regexp_icmp_ingress_cmt, record.rule)[2], # type
                regex(local.regexp_icmp_ingress_cmt, record.rule)[3]  # code
            )
            source = regex(local.regexp_icmp_ingress_cmt, record.rule)[0]
            destination = null
            description = regex(local.regexp_icmp_ingress_cmt, record.rule)[4]
        } if can(regex(local.regexp_icmp_ingress_cmt, record.rule))
    }
  } 
}
// output sl_lex_icmp_ingress_cmt {
//     value = local.sl_lex_icmp_ingress_cmt
// }

# process simplified ingress icmp pattern
locals {
  sl_lex_icmp_ingress = {
    for key, value in local.sl_lex_indexed : 
    key => {
        for record in value :
        record._position => {
            _position   = record._position
            _format     = "regexp_icmp_ingress"

            _source     = record.rule
            _regexp     = local.regexp_icmp_ingress

            protocol    = format("icmp/%s.%s",
                regex(local.regexp_icmp_ingress, record.rule)[2], # type
                regex(local.regexp_icmp_ingress, record.rule)[3]  # code
            )
            source = regex(local.regexp_icmp_ingress, record.rule)[0]
            destination = null
            description = null
        } if can(regex(local.regexp_icmp_ingress, record.rule))
    }
  } 
}
// output sl_lex_icmp_ingress {
//     value = local.sl_lex_icmp_ingress
// }


# process simplified egress icmp pattern with comment
locals {
  sl_lex_icmp_egress_cmt = {
    for key, value in local.sl_lex_indexed : 
    key => {
        for record in value :
        record._position => {
            _position   = record._position
            _format     = "regexp_icmp_egress_cmt"

            _source     = record.rule
            _regexp     = local.regexp_icmp_egress_cmt

            protocol    = format("icmp/%s.%s",
                regex(local.regexp_icmp_egress_cmt, record.rule)[0], # type
                regex(local.regexp_icmp_egress_cmt, record.rule)[1]  # code
            )
            source = null
            destination = regex(local.regexp_icmp_egress_cmt, record.rule)[3]

            description = regex(local.regexp_icmp_egress_cmt, record.rule)[4]
        } if can(regex(local.regexp_icmp_egress_cmt, record.rule))
    }
  } 
}
// output sl_lex_icmp_egress_cmt {
//     value = local.sl_lex_icmp_egress_cmt
// }

# process simplified egress icmp pattern
locals {
  sl_lex_icmp_egress = {
    for key, value in local.sl_lex_indexed : 
    key => {
        for record in value :
        record._position => {
            _position   = record._position
            _format     = "regexp_icmp_egress"

            _source     = record.rule
            _regexp     = local.regexp_icmp_egress

            protocol    = format("icmp/%s.%s",
                regex(local.regexp_icmp_egress, record.rule)[0], # type
                regex(local.regexp_icmp_egress, record.rule)[1]  # code
            )
            source = null
            destination = regex(local.regexp_icmp_egress, record.rule)[3]

            description = null
        } if can(regex(local.regexp_icmp_egress, record.rule))
    }
  } 
}
// output sl_lex_icmp_egress {
//     value = local.sl_lex_icmp_egress
// }

locals {
  // generate sorted positions for each key
  sl_lex_positions_per_key = {
    for key, value in local.sl_lex_indexed : 
      key =>
      sort(formatlist("%010d", [for rule in value : rule._position]))
  }
}
// output "sl_lex_positions_per_key" {
//   value = local.sl_lex_positions_per_key
// }

locals {
  sl_lex = {
    for key, entry in local.sl_lex_indexed :
      key => {
      rules = [
        for position in local.sl_lex_positions_per_key[key]:

            // data is kept in separate data structures because of processing limitations
            // this is a moment when all pieces are collected togeher
            // Note that each interm data dtructure keeps distinct set of data,
            // what is guaranteed by processing filters.  
            can(local.sl_lex_egress[key][tonumber(position)])
                ? local.sl_lex_egress[key][tonumber(position)] 
                : can(local.sl_lex_ingress[key][tonumber(position)])
                    ? local.sl_lex_ingress[key][tonumber(position)] 
                    : can(local.sl_lex_egress_dst[key][tonumber(position)])
                        ? local.sl_lex_egress_dst[key][tonumber(position)] 
                        : can(local.sl_lex_ingress_dst[key][tonumber(position)])
                            ? local.sl_lex_ingress_dst[key][tonumber(position)] 
                            : can(local.sl_lex_ingress_dst_cmt[key][tonumber(position)])
                                ? local.sl_lex_ingress_dst_cmt[key][tonumber(position)] 
                                : can(local.sl_lex_icmp_ingress_cmt[key][tonumber(position)])
                                    ? local.sl_lex_icmp_ingress_cmt[key][tonumber(position)] 
                                    : can(local.sl_lex_icmp_ingress[key][tonumber(position)])
                                        ? local.sl_lex_icmp_ingress[key][tonumber(position)] 
                                        : can(local.sl_lex_icmp_egress[key][tonumber(position)])
                                            ? local.sl_lex_icmp_egress[key][tonumber(position)] 
                                            : can(local.sl_lex_icmp_egress_cmt[key][tonumber(position)])
                                                ? local.sl_lex_icmp_egress_cmt[key][tonumber(position)] 
                                                : local.sl_lex_egress_error[0]
      ]
    } 
  }
}
output "result_sl_lex" {
  value = local.sl_lex
}


