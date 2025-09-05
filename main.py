import time
from discord_webhook import DiscordEmbed, DiscordWebhook
import yfinance as yf
from datetime import datetime, timedelta
import numpy as np
from sklearn.linear_model import LinearRegression
from sklearn.preprocessing import PolynomialFeatures
import matplotlib.pyplot as plt
import statistics as stats
import os, configparser, requests

config = {}
data = {}


def testconfig(symbol, url):
    if not symbol or symbol.lower() == '{insert-stock-symbol}':
        return False
    if not url or url.lower() == '{insert-discord-webhook-url}':
        return False
    return True
    # test url to be added later


# Configuration
def configure():
    configer = configparser.ConfigParser()
    if os.path.isfile('config.ini'):
        configer.read('config.ini')

        symbol = configer.get('General', 'symbol')
        WEBHOOK_URL = configer.get('General', 'webhook_url')

        days = configer.getint('Model_Tuning', 'days', fallback=90)
        degree = configer.getint('Model_Tuning', 'degree', fallback=4)
        zlimit = configer.getfloat('Model_Tuning', 'zlimit', fallback=2.0)

        if not testconfig(symbol, WEBHOOK_URL):
            print("Invalid configuration. Please check your 'config.ini' file.")
            print("Make sure the stock symbol and Discord webhook URL are correctly set.")
            exit()

        global config
        config = {
            'symbol': symbol,
            'webhook_url': WEBHOOK_URL,
            'days': days,
            'degree': degree,
            'zlimit': zlimit
        }

    else:
        # Create Configuration file
        configer['General'] = {'symbol':'{insert-stock-symbol}', 'webhook_url': '{insert-discord-webhook-url}'}
        # Add way to run multiple stocks in the future

        configer['Model_Tuning'] = {'days': '90', 'polnomial_degree': '4', 'zlimit': '2.0'}

        # Write the configuration to a file
        with open('config.ini', 'w') as configfile:
            configer.write(configfile)

        print("Configuration file created. Please edit 'config.ini' with your stock symbol and Discord webhook URL.")
        exit()

def collectdata():
    # Fetch data
    start_date = datetime.now() - timedelta(days=config['days'])
    end_date = datetime.now()
    ticker = yf.Ticker(config['symbol'])
    datas = ticker.history(start=start_date, end=end_date)

    # Prepare data
    cps = datas['Close'].tolist()
    count = len(cps)
    x = np.linspace(1, count, count).reshape(-1, 1)
    close = np.array(cps)

    # Polynomial Regression
    poly = PolynomialFeatures(degree=config['degree'])
    X_poly = poly.fit_transform(x)
    poly.fit(X_poly, close)
    pol = LinearRegression()
    pol.fit(X_poly, close)

    # Linear Regression
    lin = LinearRegression()
    lin.fit(x, close)

    # Calculate error between linear and polynomial regression
    err = []
    for i in range(count):
        i = np.array([[i]])
        linear = lin.predict(i)[0]
        polyno = pol.predict(poly.fit_transform(i))[0]
        err.append(linear - polyno)
    mean = stats.mean(err)
    stdev = stats.stdev(err)

    # Predict
    guess = np.array([[count + 1]])
    polyguess = pol.predict(poly.fit_transform(guess))[0]
    linguess = lin.predict(guess)[0]
    prederr = polyguess - linguess
    zscore = abs((prederr - mean) / stdev)
    
    global data
    data = {
        'cps': cps,
        'x': x,
        'close': close,
        'poly': poly,
        'pol': pol,
        'lin': lin,
        'polyguess': polyguess,
        'linguess': linguess,
        'zscore': zscore
    }

def sendalert():
    # if data['zscore'] > config['zlimit']:
        # Send Alert
    plt.plot(data['x'], data['close'], color='red', label='Actual')
    plt.plot(data['x'], data['pol'].predict(data['poly'].fit_transform(data['x'])),
            color='blue', label='PolyReg')
    plt.plot(data['x'], data['lin'].predict(data['x']), color='green', label='LinReg')
    plt.xlabel('Days')
    plt.ylabel('Price')
    plt.legend()
    filename = "stockplot.png"
    plt.savefig(filename, dpi=300, bbox_inches='tight', facecolor='#ababab', transparent=True)
    plt.close() 

    content = f"""
Last price: ${data['cps'][-1]:.2f}
Predicted price: ${data['polyguess']:.2f}
Z-Score: {data['zscore']:.2f}
"""
    webhook = DiscordWebhook(url=config['webhook_url'], content=f"It's a great time to buy {config['symbol']}") #
    with open(filename, "rb") as f:
        webhook.add_file(file=f.read(), filename=filename) #
    embed = DiscordEmbed(title=config['symbol'], description=content, color="03b2f8")
    embed.set_image(url=f"attachment://{filename}")  #
    webhook.add_embed(embed)  
    response = webhook.execute() 
    os.remove(filename)

    if response and response.status_code in [200, 204]: 
        print(f"Image sent to Discord - {time.ctime()}")
    else:
        print(f"Failed to send image to Discord. Status code: {response.status_code if response else 'N/A'}")
        print(f"Response: {response.text if response else 'N/A'}")

if __name__ == "__main__":
    configure()
    collectdata()
    sendalert()