(use-modules (ice-9 match)
             (ice-9 rdelim)
             (ice-9 regex)
             (srfi srfi-1))

(define constants
  '((left 0)
    (right 1)
    (up 2)
    (down 3)
    (scale-down 0)
    (scale-fit 1)
    (scale-width 2)
    (scale-height 3)
    (scale-zoom 4)
    (degree-90 1)
    (degree-180 2)
    (degree-270 3)
    (flip-horizontal 0)
    (flip-vertical 1)))

(define-syntax const
  (syntax-rules ()
    ((_ name)
     (cadr (assoc 'name constants)))))

(it-switch-mode)

(define *input* "")
(define *slideshow*)

(define (start-slideshow rand time)
  (define (slideshow-proc n cnt time)
    (display `(sleeping ,time))
    (sleep time)
    (yield)
    (let ((next (if n
                    (if (< (+ n 1) cnt)
                        (+ n 1)
                        0)
                    (random cnt))))
      (display (list 'next next))
      (it-n-or-last (+ next 1))
      (display 'redraw)
      (it-redraw)
      (display 'iter)
      (slideshow-proc (if n next n) cnt time)))
  (set! *slideshow*
        ;; this should run in a separate thread, but imlib_render_image_part_on_drawable_at_size hangs that way
        (slideshow-proc (if rand #f (p-get-file-index)) (p-get-file-count) time))
  (set! *waiter* (lambda (key ctrl mod1)
                   (cancel-thread *slideshow*)
                   (set! *waiter* default-waiter)
                   #t))
  #t)

(define (take-up-to lst k)
  (if (>= (length lst) k)
      (take lst k)
      lst))

(define (parse-page host page regexp)
  (define (load-page host page)
    (define* (read-string port #:optional (result ""))
      (let ((line (read-char port)))
        (if (eof-object? line)
            result
            (read-string port (string-append result (string line))))))
    (let* ((ai (car (getaddrinfo host "http")))
           (s  (socket (addrinfo:fam ai)
                       (addrinfo:socktype ai)
                       (addrinfo:protocol ai))))
      (connect s (addrinfo:addr ai))
      (display (string-append "GET /" page " HTTP/1.1\n"
                              "User-Agent: sxiv\n"
                              "Host: " host "\n"
                              "Accept: text/html\n"
                              "Connection: close\n\n")
               s)
      (read-string s)))
  (map (lambda (match) (match:substring match 1))
       (list-matches regexp
                     (load-page host page))))

(define (sort-of-url-encode str)
  (string-map (lambda (c) (if (eqv? c #\space)
                         #\+
                         c))
              str))

(define (load-imgur-images raw-query page max-galleries max-images-per-gallery max-images)
  (display "loading links") (newline)
  (let* ((query (sort-of-url-encode raw-query))
         (galleries (take-up-to (filter (lambda (gallery) (not (string=? gallery "random")))
                                        (parse-page "imgur.com"
                                                    (string-append "gallery/hot/viral/day/page/"
                                                                   (number->string page)
                                                                   "/hit?scrolled&set=0&q="
                                                                   query)
                                                    "href=\"/gallery/([^\"]+)\""))
                                max-galleries))
         (images (take-up-to (append-map (lambda (gallery) (take-up-to (parse-page "imgur.com"
                                                                              (string-append "gallery/" gallery)
                                                                              "img src=\"//i.imgur.com/([a-z0-9A-Z]+\\.[a-z]+)\"")
                                                                  max-images-per-gallery))
                                         galleries)
                             max-images))
         (directory (string-append "/tmp/" query "-" (number->string (random (* 42 42))) "/")))
    (display "links are loaded") (newline)
    (system (string-append "mkdir " directory))
    (map (lambda (image) (begin
                      (display (string-append "loading http://i.imgur.com/" image)) (newline)
                      (system (string-append "wget -qO " directory image " http://i.imgur.com/" image))
                      (it-add-image (string-append directory image))))
         images)
    #t))


(define (apply-input-to func)
  (display "waiting for an input")
  (newline)
  (set! *input* "")
  (set! *waiter*
        (lambda (key ctrl mod1)
          (let ((char (integer->char key)))
            (cond ((and ctrl
                        (eqv? (integer->char (+ key 96)) #\g))
                   (begin (set! *waiter* default-waiter)
                          #t))
                  ((eqv? char #\return) (begin
                                          (set! *waiter* default-waiter)
                                          (func *input*)
                                          #t))
                  ((eqv? char #\backspace) (begin (set! *input* (xsubstring *input*
                                                                            0
                                                                            (- (string-length *input*) 1)))
                                                  (p-set-bar-left *input*)
                                                  #t))
                  ((<= key 31) #f)
                  (else (begin (set! *input* (string-append *input* (string char)))
                               (p-set-bar-left *input*)
                               #t))))))
  (p-set-bar-left "")
  #t)

(define (apply-numeric-input-to func)
  (apply-input-to (lambda (numstr)
                    (func (if (string->number numstr)
                              (string->number numstr)
                              0)))))

(define (default-waiter key ctrl mod1)
  ;(newline)
  (display (list 'command key ctrl mod1))
  (newline)
  (if (> key 0)
      (if ctrl
          (match (integer->char (+ key 96))
            (#\6 (i-alternate))
            (#\n (i-navigate-frame 1))
            (#\p (i-navigate-frame -1))
            (#\m (i-toggle-animation))
            (#\h (it-scroll-screen (const left)))
            (#\j (it-scroll-screen (const down)))
            (#\k (it-scroll-screen (const up)))
            (#\l (it-scroll-screen (const right)))
            (#\e (apply-input-to (lambda (str) (p-set-bar-left (object->string (eval-string str))))))
            (#\a (apply-input-to it-add-image))
            (#\s (start-slideshow #f 2))
            (#\i (apply-input-to (lambda (query) (load-imgur-images query 0 15 5 50))))
            (else #f))
          (match (integer->char key)
            (#\q (it-quit))
            (#\return (it-switch-mode))
            (#\f (it-toggle-fullscreen))
            (#\b (it-toggle-bar))
            (#\r (it-reload-image))
            (#\R (t-reload-all))
            (#\D (it-remove-image))
            (#\n (i-navigate 1))
            (#\space (i-navigate 1))
            (#\p (i-navigate -1))
            (#\backspace (i-navigate -1))
            (#\g (it-first))
            (#\G (apply-numeric-input-to it-n-or-last))
            (#\h (apply-numeric-input-to (lambda (num) (it-scroll-move (const left) num))))
            (#\j (apply-numeric-input-to (lambda (num) (it-scroll-move (const down) num))))
            (#\k (apply-numeric-input-to (lambda (num) (it-scroll-move (const up) num))))
            (#\l (apply-numeric-input-to (lambda (num) (it-scroll-move (const right) num))))
            (#\H (i-scroll-to-edge (const left)))
            (#\J (i-scroll-to-edge (const down)))
            (#\K (i-scroll-to-edge (const up)))
            (#\L (i-scroll-to-edge (const right)))
            (#\+ (i-zoom 1))
            (#\- (i-zoom -1))
            (#\= (i-set-zoom 100))
            (#\w (i-fit-to-win (const scale-fit)))
            (#\e (i-fit-to-win (const scale-width)))
            (#\E (i-fit-to-win (const scale-height)))
            (#\W (i-fit-to-img))
            (#\< (i-rotate (const degree-270)))
            (#\> (i-rotate (const degree-90)))
            (#\? (i-rotate (const degree-180)))
            (#\| (i-flip (const flip-horizontal)))
            (#\_ (i-flip (const flip-vertical)))
            (#\a (i-toggle-antialias))
            (#\A (it-toggle-alpha))
            (else #f)))
      #f))

(define *waiter* default-waiter)

(define (on-key-press key ctrl mod1)
  (*waiter* key ctrl mod1))

(define (on-button-press button ctrl x y)
  (display (list button ctrl x y))
  (match button
    (4 (if ctrl
           (it-scroll-move (const left) 42)
           (it-scroll-move (const up) 42)))
    (5 (if ctrl
           (it-scroll-move (const right) 42)
           (it-scroll-move (const down) 42)))
    (2 (it-toggle-fullscreen))
    (1 (i-navigate 1))
    (3 (i-navigate -1))
    (else #f)))
