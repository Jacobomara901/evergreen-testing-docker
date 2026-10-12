use strict;
use warnings;
use OpenSRF::System;
use OpenSRF::Utils::Config;

OpenSRF::System->bootstrap_client(config_file => '/openils/conf/opensrf_core.xml');

my $session = OpenSRF::AppSession->create('opensrf.settings');
exit 1 unless $session->connect;
exit 1 unless $session->request(
    'opensrf.settings.host_config.get',
    OpenSRF::Utils::Config->current->env->hostname
);
exit 0;
