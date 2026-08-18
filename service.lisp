(:repo-name    'save-dapla-deploy'
 :system-name  'save-dapla-deploy'
 :fqdn         'save.dapla.net'
 :vhost-name   'save'
 :service-user 'archivebox'
 :description  'ArchiveBox web archiver'
 :image        'oci.dapla.net/archivebox/archivebox:latest'
 :internal-port 8000
 :health-path  '/'
 :extra-envs ('ALLOWED_HOSTS=save.dapla.net'
               'MEDIA_MAX_SIZE=512m')
 :datasets
 (  (:name 'users/archivebox'
   :mountpoint '/var/lib/archivebox'
   :purpose 'Service account home directory')
  (:name 'containers/archivebox'
   :mountpoint '/srv/archivebox'
   :purpose 'ArchiveBox SQLite index and snapshots'))
)
