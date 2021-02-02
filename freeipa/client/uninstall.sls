{%- from "freeipa/map.jinja" import client, ipa_host, ipa_servers with context %}


freeipa_client_uninstall:
  cmd.run:
    - name: >
        ipa-client-install --uninstall
