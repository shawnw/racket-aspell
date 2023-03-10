#lang info
(define collection "aspell")
(define deps '("base"))
(define build-deps '("scribble-lib" "racket-doc" "rackunit-lib"))
(define scribblings '(("scribblings/aspell.scrbl" () ("Tool Libraries"))))
(define pkg-desc "Interface to the GNU aspell spell checker")
(define version "0.0")
(define pkg-authors '(shawnw))
(define license 'LGPL-3.0-or-later)
