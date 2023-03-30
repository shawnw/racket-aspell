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

(require racket/class racket/contract racket/dict racket/list racket/match racket/string)
(module+ test (require rackunit))

(provide
 (contract-out
  [aspell? predicate/c]
  [aspell-active? (-> aspell? boolean?)]
  [open-aspell (->* () (#:aspell-path (or/c path-string? #f)
                        #:dict (or/c string? #f)
                        #:personal-dict (or/c path-string? #f)
                        #:dict-dir (or/c path-string? #f)
                        #:lang (or/c string? #f)
                        #:mode (or/c symbol? #f)
                        #:ignore-case boolean?
                        )
                    aspell?)]
  [close-aspell (-> aspell? void?)]
  [aspell-language (-> aspell? string?)]
  [aspell-add-word (->* (aspell? string?) ((or/c string? 'personal 'session)) void?)]
  [aspell-get-dictionary (->* (aspell?) ((or/c 'personal 'session)) (listof string?))]
  [aspell-save-dictionary (-> aspell? void?)]
  [aspell-check (-> aspell? string? list?)]
  [aspell-logger logger?]
  [aspell-executable-path (parameter/c (or/c path-string? #f))]
  [aspell-compatibility-mode (parameter/c (or/c 'aspell 'ispell 'hunspell))]
  ))

(define aspell-executable-path (make-parameter (find-executable-path "aspell")))
(define aspell-compatibility-mode (make-parameter 'aspell))
(define aspell-logger (make-logger 'aspell))

(define (path-string->string ps)
  (if (path? ps)
      (path->string ps)
      ps))

(define ispell%
  (class object%
    (super-new)

    (init-field custodian)
    (field [stdin #f] [stdout #f] [stderr #f] [process #f] [error-logging-thread #f])

    (define/public (close)
      (log-message aspell-logger 'info "stopping aspell")
      (close-output-port stdin)
      (close-input-port stdout)
      (kill-thread error-logging-thread)
      (close-input-port stderr)
      (subprocess-wait process)
      (custodian-shutdown-all custodian))

    (define (read-results)
      (for/list ([line (in-lines stdout 'any)]
                 #:break (string=? line "")
                 #:when (not (string=? line "*")))
        (match line
          ((pregexp #px"^# (\\S+) (\\d+)" (list _ word offset))
           (list word (string->number offset)))
          ((pregexp #px"^& (\\S+) \\d+ (\\d+): (.*)" (list _ word offset guesses))
           (list* word (string->number offset) (regexp-split #px",\\s+" guesses))))))

    (define/public (spellcheck-line line)
      (write-char #\^ stdin)
      (write-string line stdin)
      (newline stdin)
      (read-results))

    (define (ispell-command-line-args dict personal-dict dict-dir lang mode ignore-case)
      (when dict-dir
        (log aspell-logger 'warning "#:dict-dir option unsupported with ispell"))
      (when lang
        (log aspell-logger 'warning "#:lang option unsupported with ispell"))
      (when ignore-case
        (log aspell-logger 'warning "#:ignore-case option unsupported with ispell"))
      (values (append
               (if dict (list "-d" (path-string->string dict)) '())
               (if personal-dict (list "-p" (path-string->string personal-dict)) '())
               (case mode
                 ((tex) '("-t"))
                 ((nroff) '("-n"))
                 ((html sgml) '("-H"))
                 ((text none) '("-o"))
                 (else '())))
              '()))

    (define/pubment (command-line-args dict personal-dict dict-dir lang mode ignore-case)
      (let-values ([(args env)
                    (inner
                     (ispell-command-line-args dict personal-dict dict-dir lang mode ignore-case)
                     command-line-args dict personal-dict dict-dir lang mode ignore-case)])
      (values (append args '("-a")) env)))

    (define/public (set-terse-mode)
      (write-bytes #"!\n" stdin))
    (define/public (save-personal-dictionary)
      (write-bytes #"#\n" stdin))
    (define/public (save-word-for-session word)
      (write-byte #"@ " stdin)
      (write-bytes (string->bytes/locale word) stdin)
      (newline stdin))
    (define/public (insert-word-into-dictionary word)
      (write-byte #"* " stdin)
      (write-bytes (string->bytes/locale word) stdin)
      (newline stdin))
    (define/public (add-replacement-word word replacement)
      (raise-user-error 'aspell-add-word "replacement words not supported"))
    (define/public (get-personal-dictionary)
      (raise-user-error 'aspell-get-dictionary "operation not supported"))
    (define/public (get-session-dictionary)
      (raise-user-error 'aspell-get-dictionary "operation not supported"))
    (define/public (get-language)
      (raise-user-error 'aspell-language "operation not supported"))))

(define (aspell? obj)
  (is-a? obj ispell%))

(define aspell%
  (class ispell%
    (super-new)

    (inherit-field stdin stdout)

    (define/augment (command-line-args master-dict personal-dict dict-dir lang mode ignore-case)
      (values (filter-map (lambda (arg)
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
                            (ignore-case . ,ignore-case)
                            (encoding . "utf-8")
                            (suggest . #t)))
              '()))

    (define/override (save-word-for-session word)
      (write-bytes #"@ " stdin)
      (write-string word stdin)
      (newline stdin))
    (define/override (insert-word-into-dictionary word)
      (write-bytes #"* " stdin)
      (write-string word stdin)
      (newline stdin))
    (define/override (add-replacement-word word replacement)
      (fprintf stdin "$$ra ~a,~a~%" word replacement))

    (define (read-dictionary)
      (match (read-line stdout 'any)
        ("0:" '())
        ((pregexp #px"^\\d+: (.*)" (list _ words))
         (regexp-split #px",\\s+" words))))

    (define/override (get-personal-dictionary)
      (write-bytes #"$$pp\n" stdin)
      (read-dictionary))

    (define/override (get-session-dictionary)
      (write-bytes #"$$ps\n" stdin)
      (read-dictionary))

    (define/override (get-language)
      (write-bytes #"$$l\n" stdin)
      (read-line stdout 'any))))

(define hunspell%
  (class ispell%
    (super-new)
    (inherit-field stdin)

    (define/augment (command-line-args master-dict personal-dict dict-dir lang mode ignore-case)
      (when lang
        (log aspell-logger 'warning "#:lang option unsupported with hunspell"))
      (when ignore-case
        (log aspell-logger 'warning "#:ignore-case option unsupported with hunspell"))
      (values
       (append
        (case mode
          ((tex) '("-t"))
          ((nroff) '("-n"))
          ((xml) '("-X"))
          ((sgml html) '("-H"))
          ((odf) '("-O"))
          (else '()))
        (if master-dict (list "-d" (path-string->string master-dict)) '())
        '("-i" "utf-8"))
       (if dict-dir `(("DICPATH" . ,(path-string->string dict-dir))) '())))

    (define/override (save-word-for-session word)
      (write-bytes #"@ " stdin)
      (write-string word stdin)
      (newline stdin))
    (define/override (insert-word-into-dictionary word)
      (write-bytes #"* " stdin)
      (write-string word stdin)
      (newline stdin))
))

(define (log-stderr stderr)
  (let ([line (read-line stderr 'any)])
    (unless (eof-object? line)
      (log-message aspell-logger 'warning line)
      (log-stderr stderr))))

(define (read-line-avail port)
  (let* ([bs (make-bytes 4096)]
         [nbytes (read-bytes-avail!* bs port)])
    (if (= nbytes 0)
       ""
       (let ([lines (string-split (bytes->string/utf-8 bs #f 0 nbytes) #rx"\r?\n")])
         (if (null? lines)
             ""
             (car lines))))))
 
(define (open-aspell #:aspell-path [aspell-path (aspell-executable-path)] #:dict [master-dict #f] #:personal-dict [personal-dict #f] #:dict-dir [dict-dir #f] #:lang [lang #f]
                     #:mode [mode #f] #:ignore-case [ignore-case #f])
  (unless aspell-path
    (raise-user-error 'open-aspell "No aspell binary found"))
  (define aspell-custodian (make-custodian))
  (define aspell-obj (make-object (case (aspell-compatibility-mode)
                                    ((aspell) aspell%)
                                    ((hunspell) hunspell%)
                                    ((ispell) ispell%))
                       aspell-custodian))
  (parameterize ([current-custodian aspell-custodian]
                 [current-subprocess-custodian-mode 'kill]
                 [current-environment-variables (current-environment-variables)])
    (let-values ([(args env) (send aspell-obj command-line-args master-dict personal-dict dict-dir lang mode ignore-case)])
      (for ([(name val) (in-dict env)])
        (putenv name val))
      (let-values ([(process stdout stdin stderr)
                    (apply subprocess #f #f #f aspell-path args)])
        (sync process stdout) ; Wait for process to write something or exit
        (cond
          ((not (eq? (subprocess-status process) 'running))
           (let ([errmsg (format "aspell failed to run~%  exit status: ~A~%  stderr: ~S" (subprocess-status process) (read-line-avail stderr))])
             (log-message aspell-logger 'error errmsg)
             (custodian-shutdown-all aspell-custodian)
             (raise-user-error 'open-aspell errmsg)))
          (else
           (log-message aspell-logger 'info "starting aspell")
           (file-stream-buffer-mode stdin 'none)
           (file-stream-buffer-mode stdout 'none)
           (file-stream-buffer-mode stderr 'none)
           (read-bytes-line stdout 'any) ; Read and discard banner line
           (set-field! process aspell-obj process)
           (set-field! stdin aspell-obj stdin)
           (set-field! stdout aspell-obj stdout)
           (set-field! stderr aspell-obj stderr)
           (set-field! error-logging-thread aspell-obj (thread (lambda () (log-stderr stderr))))
           (send aspell-obj set-terse-mode) ; Set terse mode
           aspell-obj))))))

(define (aspell-active? a)
  (eq? (subprocess-status (get-field process a)) 'running))

(define (close-aspell a)
  (send a close))

;; Return the language being used
(define (aspell-language a)
  (send a get-language))

;; Add a word to the personal or session dictionary
(define (aspell-add-word a word [replacement 'personal])
  (cond
    ((string? replacement)
     (void (send a save-replacement-word word replacement)))
    ((eq? replacement 'session)
     (void (send a save-word-for-session word)))
    ((eq? replacement 'personal)
     (void (send a insert-word-into-dictionary word)))))

(define (aspell-get-dictionary a [dict-type 'personal])
  (case dict-type
    ((personal) (send a get-personal-dictionary))
    ((session) (send a get-session-dictionary))))

; Save the current personal dictionary
(define (aspell-save-dictionary a)
  (void (send a save-personal-dictionary)))

(define %spellcheck-line (generic ispell% spellcheck-line))
(define (aspell-check a text)
  (for*/list ([line (regexp-split #rx"\n+" text)]
              [result (in-list (send-generic a %spellcheck-line line))]
              #:unless (null? result))
    result))

(module+ test

  (define aspell-path (find-executable-path "aspell"))

  ; Only run tests when aspell is present
  (when aspell-path
    (define speller (open-aspell #:aspell-path aspell-path #:lang "en_US"))
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
    (check-false (aspell-active? speller)))
  )
