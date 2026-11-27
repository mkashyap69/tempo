Apple's root certificates go here before `docker build` (public files; not committed):

    curl -fO https://www.apple.com/certificateauthority/AppleRootCA-G3.cer
    curl -fO https://www.apple.com/certificateauthority/AppleRootCA-G2.cer
    curl -fO https://www.apple.com/certificateauthority/AppleIncRootCertificate.cer

The api verifies StoreKit 2 and App Store Server Notification signatures against them.
