;;;; src/deploy.lisp -- save-dapla-deploy/deploy core package
;;;;
;;;; Consfigurator properties and DEFHOST for ArchiveBox at save.dapla.net.
;;;; ArchiveBox stores full snapshots of web pages; its data directory holds
;;;; the SQLite index, downloaded media, and HTML snapshots on the ZFS data
;;;; dataset.

(defpackage :save-dapla-deploy/deploy
  (:use :cl)
  (:import-from :consfigurator
                :defprop :defhost :mrun :stripln
                :remote-exists-p :write-remote-file :on-change)
  (:import-from :consfigurator.property.file
                :has-content :containing-directory-exists)
  (:import-from :consfigurator.property.systemd :lingering-enabled)
  (:import-from :consfigurator.property.service :reloaded)
  (:export :*service-user* :*home-dataset* :*home-mountpoint*
           :*data-dataset* :*data-mountpoint*
           :*home-dataset-keyfile* :*data-dataset-keyfile*
           :*haproxy-fqdn*
           :deploy-app
           :zfs-encryption-key :zfs-dataset-mounted
           :rootless-service-account
           :images-pulled :quadlets-activated
           :cinix-write-string
           :service-account-uid
           :quadlets-written
           :haproxy-vhost-written
           :save-network-sections
           :save-container-sections
           :haproxy-vhost-config))

(in-package :save-dapla-deploy/deploy)

(defparameter *service-user* "archivebox")
(defparameter *home-dataset* "storage/users/archivebox")
(defparameter *home-mountpoint* "/var/lib/archivebox")
(defparameter *home-dataset-keyfile* "/etc/zfs-keys/archivebox-users.key")
(defparameter *data-dataset* "storage/containers/archivebox")
(defparameter *data-mountpoint* "/srv/archivebox"
  "ArchiveBox data directory: SQLite index, snapshots, and media.")
(defparameter *data-dataset-keyfile* "/etc/zfs-keys/archivebox-data.key")
(defparameter *haproxy-fqdn* "save.dapla.net")
(defparameter *haproxy-vhost-name* "save")

(defprop zfs-encryption-key :posix (path)
  "Generate a raw 32-byte ZFS encryption key at PATH, once, left alone on redeploy."
  (:desc (format nil "ZFS encryption key at ~A" path))
  (:check (remote-exists-p path))
  (:apply
   (containing-directory-exists path)
   (write-remote-file path (mrun "openssl" "rand" "32") :mode #o600)))

(defun zfs-create-command (dataset mountpoint keyfile)
  (if keyfile
      (format nil "zfs create -o mountpoint=~A -o encryption=aes-256-gcm -o keyformat=raw -o keylocation=file://~A ~A"
              mountpoint keyfile dataset)
      (format nil "zfs create -o mountpoint=~A ~A" mountpoint dataset)))

(defprop zfs-dataset-mounted :posix (dataset mountpoint &optional keyfile)
  "Ensure DATASET exists, mounted at MOUNTPOINT, AES-256-GCM encrypted when KEYFILE is supplied."
  (:desc (format nil "ZFS dataset ~A mounted at ~A~:[~; (encrypted)~]" dataset mountpoint keyfile))
  (:check
   (multiple-value-bind (out err exit)
       (consfigurator:run :may-fail (format nil "zfs get -H -o value mounted ~A" dataset))
     (declare (ignore err))
     (and (zerop exit) (string= "yes" (stripln out)))))
  (:apply
   (if (zerop (mrun :for-exit (format nil "zfs list -H -o name ~A" dataset)))
       (progn (when keyfile (mrun (format nil "zfs load-key ~A" dataset)))
              (mrun (format nil "zfs mount ~A" dataset)))
       (mrun (zfs-create-command dataset mountpoint keyfile)))))

(defprop rootless-service-account :posix (username home)
  "Ensure system account USERNAME exists with home HOME, without creating the directory."
  (:desc (format nil "System account ~A at ~A" username home))
  (:check (zerop (mrun :for-exit "id" username)))
  (:apply (mrun "useradd" "--system" "--no-create-home" "--home-dir" home username)))

(defprop images-pulled :posix (user &rest images)
  "Pull IMAGES into USER's rootless Podman image store via `machinectl shell`."
  (:desc (format nil "Podman images pulled for ~A" user))
  (:check (every (lambda (i) (zerop (mrun :for-exit (format nil "machinectl shell ~A@ /usr/bin/podman image exists ~A" user i)))) images))
  (:apply (dolist (i images) (mrun (format nil "machinectl shell ~A@ /usr/bin/podman pull ~A" user i)))))

(defun cinix-write-string (sections)
  "Serialize an alist of (section-name . ((key . value) ...)) into INI/systemd unit-file text."
  (with-output-to-string (s)
    (dolist (section sections)
      (format s "[~A]~%" (car section))
      (dolist (kv (cdr section)) (format s "~A=~A~%" (car kv) (cdr kv)))
      (format s "~%"))))

(defun service-account-uid (username)
  "Read USERNAME's UID via getent at apply time. The UID is the loopback PublishPort."
  (parse-integer
   (third (uiop:split-string
           (string-trim '(#\Newline #\Space)
             (with-output-to-string (s)
               (uiop:run-program (list "getent" "passwd" username) :output s)))
           :separator '(#\:)))))

(defun save-network-sections ()
  '(("Network" . (("NetworkName" . "save") ("Internal" . "true")))))

(defun save-container-sections (data-mountpoint)
  "Cinix AST for save.container. The loopback port is the service account UID."
  (let ((port (service-account-uid *service-user*)))
    `(("Unit"      . (("Description" . "ArchiveBox web archiver")))
      ("Container" . (("Image"         . "oci.dapla.net/archivebox/archivebox:latest")
                      ("ContainerName" . "archivebox")
                      ("AutoUpdate"    . "registry")
                      ("PublishPort"   . ,(format nil "127.0.0.1:~A:8000" port))
                      ("Volume"        . ,(format nil "~A:/data:Z" data-mountpoint))
                      ("Environment"   . "ALLOWED_HOSTS=save.dapla.net")
                      ("Environment"   . "MEDIA_MAX_SIZE=512m")
                      ("Network"       . "save.network")
                      ("Label"         . "io.containers.autoupdate=registry")))
      ("Service"   . (("Restart" . "on-failure") ("TimeoutStartSec" . "120") ("TimeoutStopSec" . "30")))
      ("Install"   . (("WantedBy" . "default.target"))))))

(defun haproxy-vhost-config ()
  "HAProxy vhost for save.dapla.net. Backend port is the service account UID."
  (let ((port (service-account-uid *service-user*)))
    (format nil
"frontend save_http
  bind *:80
  acl host_save hdr(host) -i save.dapla.net
  redirect scheme https code 301 if host_save

frontend save_https
  bind *:443 ssl crt /etc/haproxy/certs/save.dapla.net.pem alpn h2,http/1.1
  acl host_save hdr(host) -i save.dapla.net
  http-response set-header Strict-Transport-Security \"max-age=63072000; includeSubDomains; preload\"
  http-response set-header X-Content-Type-Options nosniff
  http-response set-header X-Frame-Options SAMEORIGIN
  http-response set-header Referrer-Policy strict-origin-when-cross-origin
  http-response set-header Permissions-Policy \"interest-cohort=()\"
  use_backend save_be if host_save

backend save_be
  balance roundrobin
  option httpchk GET /
  http-check expect status 200
  timeout connect 5s
  timeout server  60s
  server archivebox 127.0.0.1:~A check inter 10s rise 2 fall 3
" port)))

(defprop quadlets-activated :posix (user)
  "Reload USER's user-scope systemd daemon and restart archivebox."
  (:desc (format nil "Quadlets activated for ~A" user))
  (:apply
   (mrun (format nil "machinectl shell ~A@ /usr/bin/systemctl --user daemon-reload" user))
   (mrun (format nil "machinectl shell ~A@ /usr/bin/systemctl --user restart archivebox" user))))


(defprop quadlets-written :posix (user home data-mountpoint)
  "Write all archivebox quadlet unit files into USER's systemd container
   directory. The service account UID is read at apply time via getent,
   after ROOTLESS-SERVICE-ACCOUNT has run, so PublishPort is always correct."
  (:desc (format nil "Archivebox quadlet units written for ~A" user))
  (:apply
   (let ((quadlet-dir (format nil "~A/.config/containers/systemd" home)))
     (consfigurator.property.file:containing-directory-exists
      (format nil "~A/save.network" quadlet-dir))
     (write-remote-file
      (format nil "~A/save.network" quadlet-dir)
      (cinix-write-string (save-network-sections)))
     (write-remote-file
      (format nil "~A/save.container" quadlet-dir)
      (cinix-write-string (save-container-sections data-mountpoint))))))


(defprop haproxy-vhost-written :posix ()
  "Write the HAProxy vhost config for this service. Skipped when the
   service account does not yet exist, since the port cannot be determined.
   Reloads HAProxy only when content changes."
  (:desc (format nil "HAProxy vhost written for ~A" *haproxy-fqdn*))
  (:check (null (service-account-uid *service-user*)))
  (:apply
   (let ((port (service-account-uid *service-user*)))
     (unless port
       (consfigurator:inapplicable-property
        "Service account ~A does not exist; cannot determine port."
        *service-user*))
     (let* ((cfg-path (format nil "/etc/haproxy/conf.d/~A.cfg" *haproxy-vhost-name*))
            (new-content (haproxy-vhost-config))
            (current (when (probe-file cfg-path)
                       (uiop:read-file-string cfg-path))))
       (unless (equal new-content current)
         (containing-directory-exists cfg-path)
         (write-remote-file cfg-path new-content)
         (consfigurator.property.service:reloaded "haproxy"))))))

(defhost save-host (:deploy (:local))
  "The ArchiveBox host: two AES-256-GCM ZFS datasets, rootless service account,
   linger, pulled image, quadlet unit, and HAProxy vhost."
  (zfs-encryption-key *home-dataset-keyfile*)
  (zfs-encryption-key *data-dataset-keyfile*)
  (zfs-dataset-mounted *home-dataset* *home-mountpoint* *home-dataset-keyfile*)
  (zfs-dataset-mounted *data-dataset* *data-mountpoint* *data-dataset-keyfile*)
  (rootless-service-account *service-user* *home-mountpoint*)
  (lingering-enabled *service-user*)
  (images-pulled *service-user* "oci.dapla.net/archivebox/archivebox:latest")
  (quadlets-written *service-user* *home-mountpoint* *data-mountpoint*)
  (quadlets-activated *service-user*)
  (haproxy-vhost-written))

(defun deploy-app ()
  "Provision ArchiveBox via SAVE-HOST. Aborts loudly if any property is skipped."
  (format t "~&--> Provisioning via Consfigurator (SAVE-HOST)...~%")
  (let ((provisioning-failed nil))
    (handler-bind ((consfigurator::skipped-properties
                     (lambda (c) (declare (ignore c)) (setf provisioning-failed t))))
      (save-host))
    (when provisioning-failed
      (error "SAVE-HOST provisioning reported failed properties. Refusing to proceed.")))
  (format t "~&--> ArchiveBox provisioned. Visit https://~A~%" *haproxy-fqdn*))
