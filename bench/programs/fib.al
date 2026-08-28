// Cagri agirlikli: ozyineleme + cerceve kurma/cozme
fonk fib(n) {
    eger n < 2 { dondur n }
    dondur fib(n - 1) + fib(n - 2)
}
yazdir fib(27)
