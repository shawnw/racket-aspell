#lang racket/base
;    Racket interface to GNU ASpell
;    Copyright (C) 2022 Shawn Wagner
;
;    This program is free software: you can redistribute it and/or modify
;    it under the terms of the GNU Lesser General Public License as published by
;    the Free Software Foundation, either version 3 of the License, or
;    (at your option) any later version.
;
;    This program is distributed in the hope that it will be useful,
;    but WITHOUT ANY WARRANTY; without even the implied warranty of
;    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;    GNU General Public License for more details.
;
;    You should have received a copy of the GNU Lesser General Public License
;    along with this program.  If not, see <https://www.gnu.org/licenses/>.

(require racket/contract racket/list racket/match)
(module+ test (require rackunit))

(provide
 (contract-out
  [aspell? predicate/c]
  [aspell-active? (-> aspell? boolean?)]
  [open-aspell (->* () (#:dict (or/c string? #f)
                        #:personal-dict (or/c path-string? #f)
                        #:dict-dir (or/c path-string? #f)
                        #:lang (or/c string? #f)
                        #:mode symbol?
                        #:ignore-case boolean?
                        )
                    aspell?)]
  [close-aspell (-> aspell? void?)]
  [aspell-language (-> aspell? string?)]
  [aspell-add-word (->* (aspell? string?) ((or/c string? 'personal 'session)) void?)]
  [aspell-get-dictionary (->* (aspell?) ((or/c 'personal 'session)) (listof string?))]
  [aspell-save-dictionary (-> aspell? void?)]
  [aspell-check (-> aspell? string? list?)]
  ))

(struct aspell (process stdin stdout)
  #:extra-constructor-name make-aspell)

(define (open-aspell #:dict [master-dict #f] #:personal-dict [personal-dict #f] #:dict-dir [dict-dir #f] #:lang [lang #f]
                     #:mode [mode 'url] #:ignore-case [ignore-case #f])
  (let*-values ([(aspell-path) (find-executable-path "aspell")]
                [(args) (filter-map (lambda (arg)
                                      (let ([opt (car arg)]
                                            [val (cdr arg)])
                                        (cond
                                          ((eq? val #f) #f)
                                          ((eq? val #t) (format "--~a" opt))
                                          ((path? val)
                                           (format "--~a=~a" opt (path->string val)))
                                          (else
                                           (format "--~a=~a" opt val)))))
                                    `((master . ,master-dict)
                                      (personal . ,personal-dict)
                                      (dict-dir . ,dict-dir)
                                      (lang . ,lang)
                                      (mode . ,mode)
                                      (ignore-case . ,ignore-case)))]
                [(process stdout stdin stderr)
                 (apply subprocess #f #f 'stdout aspell-path `(,@args "--encoding=utf-8" "--suggest" "pipe"))])
    (file-stream-buffer-mode stdin 'none)
    (file-stream-buffer-mode stdout 'none)
    (read-line stdout) ; Read and discard banner line
    (write-bytes #"!\n" stdin) ; Set terse mode
    (make-aspell process stdin stdout)))

(define (aspell-active? a)
  (eq? (subprocess-status (aspell-process a)) 'running))

(define (close-aspell a)
  (close-output-port (aspell-stdin a))
  (close-input-port (aspell-stdout a))
  (subprocess-wait (aspell-process a)))

;; Return the language being used
(define (aspell-language a)
  (write-bytes #"$$l\n" (aspell-stdin a))
  (read-line (aspell-stdout a)))

;; Add a word to the personal or session dictionary
(define (aspell-add-word a word [replacement 'personal])
  (cond
    ((string? replacement)
     (fprintf (aspell-stdin a) "$$ra ~a,~a~%" word replacement))
    ((symbol? replacement)
     (fprintf (aspell-stdin a) "~A~A~%" (if (eq? replacement 'session) #\@ #\*) word))))

(define (aspell-get-dictionary a [dict-type 'personal])
  (fprintf (aspell-stdin a) "$$~A~%" (if (eq? dict-type 'session) "ps" "pp"))
  (match (read-line (aspell-stdout a))
    ("0:" '())
    ((pregexp #px"^\\d+: (.*)" (list _ words))
     (regexp-split #px",\\s+" words))))

; Save the current personal dictionary
(define (aspell-save-dictionary a)
  (write-bytes #"#\n" (aspell-stdin a))
  (void))

(define (read-results a)
  (for/list ([line (in-lines (aspell-stdout a))]
             #:break (string=? line "")
             #:when (not (string=? line "*")))
    (match line
      ((pregexp #px"^# (\\S+) (\\d+)" (list _ word offset))
       (list word (string->number offset)))
      ((pregexp #px"^& (\\S+) \\d+ (\\d+): (.*)" (list _ word offset guesses))
       (list* word (string->number offset) (regexp-split #px",\\s+" guesses))))))

(define (spellcheck-line a line)
  (write-char #\^ (aspell-stdin a))
  (write-string line (aspell-stdin a))
  (newline (aspell-stdin a))
  (read-results a))

(define (aspell-check a text)
  (for*/list ([line (regexp-split #rx"\n+" text)]
             [result (in-list (spellcheck-line a line))]
             #:when (not (null? result)))
    result))
  
(module+ test
  (define speller (open-aspell #:lang "en_US"))
  ;(displayln (aspell-language speller))

  (check-true (aspell-active? speller))
  
  (define sentence "The quick red fox juped over the lazy brown dog.")
  (define misspelled (aspell-check speller sentence))
  ;(writeln misspelled)
  (check-equal? (length misspelled) 1)
  (check-equal? (caar misspelled) "juped")

  (aspell-add-word speller "juped" 'session)
  (check-equal? (aspell-get-dictionary speller 'session) '("juped"))

  (check-equal? (aspell-check speller sentence) '())

  (close-aspell speller)
  (check-false (aspell-active? speller))

  )