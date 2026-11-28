set terminal pngcairo size 1200,700 enhanced font "Arial,13"
set output 'reports/charts/average_delay_by_route.png'

set title 'Average Delay by Route' font ",18"
set xlabel 'Route'
set ylabel 'Average Delay (minutes)'

set style data histograms
set style fill solid 0.75
set style histogram clustered gap 1

set xtics rotate by -45
set ytics 1
set grid ytics
set zeroaxis
set border 3
set key off

set yrange [-1:7]
set boxwidth 0.65

plot 'reports/charts/average_delay_sorted.dat' \
    using 2:xtic(1) with boxes lc rgb "#3985C8"
