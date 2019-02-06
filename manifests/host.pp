define perunapi::host (
  Stdlib::Fqdn              $cluster,
  Stdlib::Fqdn              $hostname   = $facts['networking']['fqdn'],
  Enum['present', 'absent'] $ensure     = 'present',
  Hash                      $attributes = {},
) {

  if $ensure == 'absent' {
    fail('Cannot remove Host via perunapi::host, use `puppet node deactivate FQDN`')
  }

  $api_user   = $perunapi::perun_api_user
  $api_host   = $perunapi::perun_api_host
  $api_passwd = $perunapi::perun_api_password

  $_query_hosts = perunapi::call(
    $api_host, $api_user, $api_passwd, 'facilitiesManager', 'getHostsByHostname',
    { 'hostname' => $hostname }, $cluster
  )
  $_host_ids = $_query_hosts.map |$_host| { $_host['id'] }

  $attributes.each |$_attr, $_attr_value| {
    if $_attr =~ /:host:/ {
      $_host_ids.each |$_host_id| {
        $_attribute = perunapi::call(
          $api_host, $api_user, $api_passwd, 'attributesManager', 'getAttribute',
          { 'host' => $_host_id, 'attributeName' => $_attr }, $cluster
        )

        if $_attr_value == 'null' {
          $_newattr = undef
        } elsif $_attr_value =~ String and $_attr_value =~ /^[0-9]*$/ {
          $_newattr = scanf($_attr_value, '%i')[0]
        } else {
          $_newattr = $_attr_value
        }

        if $_attribute['id'] and $_attribute['value'] != $_newattr {
          $_res = perunapi::call(
            $api_host, $api_user, $api_passwd, 'attributesManager', 'setAttribute',
            { 'host' => $_host_id, 'attribute' => merge($_attribute, { 'value' => $_newattr }) }, $cluster
          )

          if $_res['errorId'] and $_res['message'] {
            fail("Cannot set attribute: ${_attr}. Reason: ${_res['message']}")
          } else {
            notify { "setAttribute_${_attr}${_host_id}":
              message => "Setting attribute ${_attr} to value ${_newattr}.",
            }
          }
        }

        unless $_attribute['id'] {
          notify { "Warning: undefined attribute name ${_attr} for host ${_host_id}": }
        }
      }
    }
  }
}
