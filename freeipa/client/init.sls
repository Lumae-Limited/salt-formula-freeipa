{%- from "freeipa/map.jinja" import client, ipa_host, ipa_servers with context %}

include:
- freeipa.common
- freeipa.client.keytab
- freeipa.client.nsupdate
- freeipa.client.cert

{%- if client.install_principal is defined %}
{%- set otp = salt['random.get_str'](20) %}
{%- set install_principal = client.get('install_principal', {}) %}

freeipa_push_principal:
  file.managed:
    - name: /tmp/principal.keytab
{%- if install_principal.pillar is defined %}
    - contents_pillar: {{ install_principal.pillar }}
{%- else %}
    - source: {{ install_principal.get("source", "salt://freeipa/files/principal.keytab") }}
{%- endif %}
    - mode: {{ install_principal.get("mode", 0654) }}
    - user: {{ install_principal.get("file_user", "root") }}
    - group: {{ install_principal.get("file_group", "root") }}
    - unless:
      - ipa-client-install --unattended 2>&1 | grep "IPA client is already configured on this system"
freeipa_get_ticket:
  cmd.run:
    - name: kinit {{ install_principal.get("principal_user", "root") }}@{{ client.get("realm", "") }} -kt /tmp/principal.keytab
    - require:
      - file: freeipa_push_principal
    - onchanges:
      - file: freeipa_push_principal
freeipa_host_add:
  cmd.run:
    - name: >
        curl -k -s
        -H referer:https://{{ ipa_servers[0] }}/ipa
        --negotiate -u :
        -H "Content-Type:application/json"
        -H "Accept:applicaton/json"
        -c /tmp/cookiejar -b /tmp/cookiejar
        -X POST
        -d '{
          "id": 0,
          "method": "host_add",
                    "params": [
            [
              "{{ client.get("hostname", {})  }}"
            ],
            {
              "all": false,
              "force": false,
              "no_members": false,
              "no_reverse": false,
              "random": false,
              "raw": true,
              "userpassword": "{{ otp }}",
              "version": "2.156"
            }
          ]
        }' https://{{ ipa_servers[0] }}/ipa/json
    - require:
      - cmd: freeipa_get_ticket
    - require_in:
      - cmd: freeipa_client_install
    - onchanges:
      - file: freeipa_push_principal

freeipa_cleanup_cookiejar:
  file.absent:
    - name: /tmp/cookiejar
    - require:
      - cmd: freeipa_host_add
    - require_in:
      -cmd: freeipa_client_install
    - onchanges:
      - cmd: freeipa_host_add
freeipa_cleanup_keytab:
  file.absent:
    - name: /tmp/principal.keytab
    - require:
      - cmd: freeipa_host_add
    - require_in:
      -cmd: freeipa_client_install
    - onchanges:
      - cmd: freeipa_host_add
freeipa_kdestroy:
  cmd.run:
    - name: kdestroy
    - require:
      - cmd: freeipa_host_add
    - require_in:
      -cmd: freeipa_client_install
    - onchanges:
      - file: freeipa_push_principal
{%- endif %}

{%- if client.get('enabled', False) %}

freeipa_client_pkgs:
  pkg.installed:
    - names: {{ client.pkgs|yaml }}

freeipa_client_install:
  cmd.run:
    - name: >
        ipa-client-install
        --server {{ client.server }}
        --domain {{ client.domain }}
        {%- if client.realm is defined %} --realm {{ client.realm }}{%- endif %}
        --hostname {{ ipa_host }}
        {%- if otp is defined %}
        -w {{ otp }}
        {%- else %}
        -w {{ client.otp }}
        {%- endif %}
        {%- if client.get('mkhomedir', True) %} --mkhomedir{%- endif %}
        {%- if client.dns.updates %} --enable-dns-updates{%- endif %}
        --unattended
    - creates: /etc/ipa/default.conf
    - require:
      - pkg: freeipa_client_pkgs
    - require_in:
      - service: sssd_service
      - file: ldap_conf
      - file: krb5_conf
    {%- if client.install_principal is defined %}
    - onchanges:
      - file: freeipa_push_principal
    {%- endif %}

krb5_conf:
  file.managed:
    - name: {{ client.krb5_conf }}
    - template: jinja
    - source: salt://freeipa/files/krb5.conf

{%- endif %}
