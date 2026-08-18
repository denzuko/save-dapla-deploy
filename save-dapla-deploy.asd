;;;; save-dapla-deploy.asd

(asdf:defsystem :save-dapla-deploy)

(asdf:defsystem :save-dapla-deploy/deploy
  :description "Roswell/Consfigurator deploy of SearXNG on rootless Podman
quadlets behind HAProxy at find.dapla.net."
  :license "BSD-3-Clause"
  :depends-on (:cl-inix :consfigurator)
  :components ((:file "src/deploy"))
  :in-order-to ((asdf:test-op (asdf:test-op :save-dapla-deploy/e2e))))

(asdf:defsystem :save-dapla-deploy/docs
  :depends-on (:save-dapla-deploy/deploy :40ants-doc :40ants-doc-full)
  :components ((:file "src/docs")))

(asdf:defsystem :save-dapla-deploy/e2e
  :depends-on (:save-dapla-deploy/deploy :fiveam :dexador)
  :components ((:file "t/e2e"))
  :perform (asdf:test-op (op c)
             (uiop:symbol-call :fiveam :run! :save-dapla-deploy-e2e)))
