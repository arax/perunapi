class perunapi (
  Integer      $version            = $perunapi::params::perun_api_version,
  Stdlib::Host $perun_api_host     = $perunapi::params::perun_api_host,
  String       $perun_api_user     = $perunapi::params::perun_api_user,
  String       $perun_api_password = $perunapi::params::perun_api_password,
  Stdlib::Fqdn $cluster            = $perunapi::params::cluster,
) inherits ::perunapi::params {

  $_perunapi = lookup('perunapi')

  if empty($_perunapi) or empty($_perunapi['facility']) {
    notify { "No parameters or missing Facility for PerunAPI, skipping": }
    return()
  }

  $_query = perunapi::call(
    $perun_api_host, $perun_api_user, $perun_api_password, 'vosManager', 'getVoByShortName',
    { 'shortName' => $_perunapi['facility']['vo'] }, $cluster
  )

  if empty($_query) {
    fail("Cannot get VO ${_perunapi['facility']['vo']} ID")
  }

  perunapi::facility { $_perunapi['facility']['name']:
    ensure      => present,
    description => $_perunapi['facility']['description'],
    manager     => $_perunapi['facility']['manager'],
    owner       => $_perunapi['facility']['owner'],
    vo          => $_query['id'],
    customhosts => $_perunapi['facility']['customhosts'],
    cluster     => $cluster,
    attributes  => $_perunapi['attributes'],
    services    => $_perunapi['services'],
  }

  if $_perunapi['resources'] {
    $_perunapi['resources'].each |$_resource| {
      perunapi::resource { "${_resource['name']}${_resource['vo']}":
        ensure     => present,
        context    => $cluster,
        resource   => $_resource,
        facility   => $_perunapi['facility']['name'],
        attributes => $_perunapi['attributes'],
        services   => $_perunapi['services'],
      }
    }
  }

  perunapi::host { $_perunapi['facility']['name']:
    ensure     => present,
    cluster    => $cluster,
    attributes => $_perunapi['attributes'],
  }

  unless empty($_perunapi['pbsmon'] ) {
    perunapi::pbsmon { $_perunapi['facility']['name']:
      ensure     => present,
      context    => $cluster,
      attributes => $_perunapi['pbsmon'],
    }
  }
}
