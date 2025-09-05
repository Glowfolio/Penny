
# Penny Investment Assistant

Running on a Linux server, this investment assistant monitors real-time market data and sends alerts to Discord via webhooks whenever its indicators suggest a good time to buy. Designed for flexibility and automation, it requires some initial configuration to set up watchlists and customize signal parameters. Once deployed, it operates quietly in the background, helping you stay on top of market opportunities without constant screen-watching.


## Indicators

#### - Custom Indicator
Using a simple machine learning regression algorithm, the program creates a linear and polynomial trendline. The linear regression is supposed to model the incremental growth of the market. The polynomial is supposed to represent a dampened curve of the market's closing prices


## Hardware Used

This software is developed using Python 3.11 and a Raspberry Pi 5. In order for this work as a self maintaining server, the pi should be powered with a consistent source and has a steady internet connection (poor connection speed may affect runtime).


## Authors

- [@mastermind-mayhem](https://www.github.com/mastermind-mayhem)


## Future Plans

- Add more indicators

- Streamline installation

