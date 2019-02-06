class perunapi::params {
  $perun_api_version  = 1
  $perun_api_host     = 'perun.cesnet.cz'
  $perun_api_user     = ''
  $perun_api_password = ''

  $cluster = $trusted['domain'] =~ /cloud\.muni\.cz$/ ? {
    true    => $facts['is_cluster'] ? {
      true    => $facts['cluster']['full_name'],
      default => $facts['fqdn'],
    },
    default => empty($facts['clusterfullname']) ? {
      true    => $facts['fqdn'],
      default => $facts['clusterfullname'],
    },
  }
}
