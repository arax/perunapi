define perunapi::pbsmon (
  Array                     $attributes,
  Stdlib::Fqdn              $context,
  Enum['present', 'absent'] $ensure     = 'present',
) {

  if $ensure == 'absent' {
    fail('Cannot remove PBSMon via perunapi::pbsmon, not implemented')
  }

  $api_user   = $perunapi::perun_api_user
  $api_host   = $perunapi::perun_api_host
  $api_passwd = $perunapi::perun_api_password

  ####

  $attributes.each |$_attr| {
    case $_attr {
      /facility.*cpu/: {
        if $facts['processors']['models'][0] =~ /Intel/ {
          $_cpu = regsubst(regsubst($facts['processors']['models'][0], 'CPU.*', ''), '\(R\)', '', 'G')
        } elsif $facts['processors']['models'][0] =~ /AMD/ {
          $_cpu = regsubst($facts['processors']['models'][0], ' [0-9]*-Core.*', '')
        }

        $_value = "${facts['processors']['physicalcount']}x ${_cpu} (${facts['processors']['physicalcount']}x \
${facts['processorcorecount']} Core) ${facts['processors']['speed']}"
      }
      /facility.*network/: {
        $_speeds = $facts.filter |$_k, $_v| {
          $_k =~ /^speeds/
        }

        $_maxspeed = flatten($_speeds.values.map |$_v| {
            split($_v, ',')
        }).sort[-1]

        $_ifno = $_speeds.filter |$_k, $_v| {
          $_maxspeed in split($_v, ',')
        }.size

        if $facts['has_ibcontroller'] {
          $_ib = "1x InfiniBand ${facts['ib_speed']} Gbit/s, "
        } else {
          $_ib = ''
        }

        $_maxspeedgb = $_maxspeed / 1000

        $_value = {
          'cs' => "${_ib}${_ifno}x Ethernet ${_maxspeedgb} Gbit/s",
          'en' => "${_ib}${_ifno}x Ethernet ${_maxspeedgb} Gbit/s"
        }
      }
      /facility.*disk/: {
        $_nvme_disks = $facts['disks'].keys.filter |$_k| { $_k =~ /nvme/ }

        $_classic_disks = $facts['disks'].filter |$_k, $_v| {
          $_k =~ /^sd/ and $_v['vendor'] in ['ATA', 'HGST']
        }

        if $_nvme_disks.size > 0 {
          $_v_nvme = "${_nvme_disks.size}x${facts['disks'][$_nvme_disks[0]]['size']} SSD NVME"
        } else {
          $_v_nvme = undef
        }

        if empty($_classic_disks) {
          $_v_sd = undef
        } else {
          $_classic_disks_sizes = $_classic_disks.map |$_k, $_v| {
            $_v['size']
          }

          $_v_sd = join(unique($_classic_disks_sizes).map |$_k| {
            $_count = count($_classic_disks_sizes, $_k)
            "${_count}x ${_k} 7.2"
          }, ', ')
        }

        if $_v_nvme and $_v_sd {
          $_v = "${_v_nvme}, ${_v_sd}"
        } else {
          $_v = "${_v_nvme}${_v_sd}"
        }

        $_value = { 'cs' => $_v, 'en' => $_v }
      }
      default: { $_value = undef }
    }

    unless $_value {
      # nothing to do, end here
      return()
    }

    $_query = perunapi::call(
      $api_host, $api_user, $api_passwd, 'facilitiesManager', 'getFacilityByName',
      { 'name' => $title }, $context
    )

    unless $_query['id'] {
      fail("Unknown facility ${title}")
    }

    $_attribute = perunapi::call(
      $api_host, $api_user, $api_passwd, 'attributesManager', 'getAttribute',
      { 'facility' => $_query['id'], 'attributeName' => $_attr }, $context
    )

    if $_attribute['id'] and $_attribute['value'] != $_value {
      $_res = perunapi::call(
        $api_host, $api_user, $api_passwd, 'attributesManager', 'setAttribute',
        { 'facility' => $_query['id'], 'attribute' => merge($_attribute, { 'value' => $_value }) }, $context
      )

      if $_res['errorId'] and $_res['message'] {
        fail("Cannot set attribute: ${_attr}. Reason: ${_res}")
      } else {
        notify { "setAttribute_${_attr}":
          message => "Setting attribute ${_attr} to value ${_value}.",
        }
      }
    }
  }
}
