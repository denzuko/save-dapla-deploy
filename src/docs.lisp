;;;; src/docs.lisp -- save-dapla-deploy/docs

(defpackage :save-dapla-deploy/docs
  (:use :cl)
  (:import-from :40ants-doc :defsection))

(in-package :save-dapla-deploy/docs)

(defsection @save-dapla-deploy (:title "save-dapla-deploy")
  "Roswell/Consfigurator deploy for save.dapla.net."
  (@deploy-properties section))

(defsection @deploy-properties (:title "Consfigurator Properties")
  (save-dapla-deploy/deploy:deploy-app function))
