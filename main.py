# D.Couture
# Stock Evaluation Script

import time
from discord_webhook import DiscordEmbed, DiscordWebhook
import yfinance as yf
from datetime import datetime, timedelta
import numpy as np
from sklearn.linear_model import LinearRegression
from sklearn.preprocessing import PolynomialFeatures
import matplotlib.pyplot as plt
import statistics as stats
import os, configparser

def testconfig(symbol, url):
    if not url or url.lower() == '{insert-discord-webhook-url}':
        return False
    return True
    # test url to be added later

configer = configparser.ConfigParser()
if os.path.isfile('config.ini'):
    configer.read('config.ini')

    symbol = configer.get('General', 'symbol').split(',')
    print(symbol, type(symbol))
    WEBHOOK_URL = configer.get('General', 'webhook_url')

    days = configer.getint('Model_Tuning', 'days', fallback=90)
    degree = configer.getint('Model_Tuning', 'polynomial_degree', fallback=5)
    zlimit = configer.getfloat('Model_Tuning', 'zlimit', fallback=2.0)

    if not testconfig(symbol, WEBHOOK_URL):
        print("Invalid configuration. Please check your 'config.ini' file.")
        print("Make sure the stock symbol and Discord webhook URL are correctly set.")
        exit()

else:
    # Create Configuration file
    configer['General'] = {'symbol':'{insert-stock-symbol}', 'webhook_url': '{insert-discord-webhook-url}'}
    # Add way to run multiple stocks in the future

    configer['Model_Tuning'] = {'days': '90', 'polynomial_degree': '4', 'zlimit': '2.0'}

    # Write the configuration to a file
    with open('config.ini', 'w') as configfile:
        configer.write(configfile)

    print("Configuration file created. Please edit 'config.ini' with your stock symbol and Discord webhook URL.")
    exit()

for ssymbol in symbol:
    try:    
        print(ssymbol)
        
        # Calculate data
        # Create Models
        # Fetch data
        start_date = datetime.now() - timedelta(days=days)
        end_date = datetime.now()
        ticker = yf.Ticker(ssymbol)
        datas = ticker.history(start=start_date, end=end_date)

        # Prepare data
        cps = datas['Close'].tolist()
        count = len(cps)
        x = np.linspace(1, count, count).reshape(-1, 1)
        close = np.array(cps)

        # Polynomial Regression
        poly = PolynomialFeatures(degree=degree)
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
            err.append(linear - close[i][0][0])
        mean = stats.mean(err)
        stdev = stats.stdev(err)

        # Predict
        guess = np.array([[count + 1]])
        polyguess = pol.predict(poly.fit_transform(guess))[0]
        linguess = lin.predict(guess)[0]
        prederr = polyguess - linguess
        zscore = abs((prederr - mean) / stdev)
        azscore = abs(((cps[-1] - linguess) - mean) / stdev)
        print(azscore)

        # Condition 1: linguess > actual latest value
        print(cps[-1], linguess)
        if linguess < cps[-1]:
            content = f"""{ssymbol}  Fail-Condition 1: Linear Regression Below Close Price
        Close Price: ${cps[-1]:.2f}
        Model Prediction: ${linguess:.2f}
        """
            webhook = DiscordWebhook(url=WEBHOOK_URL, content=content)
            response = webhook.execute()
            if response and response.status_code in [200, 204]:
                print("Image Sent to Discord")
            else:
                print("Send Fail")
            continue
        # Condition 2: Z-score
        elif azscore <= zlimit:
            content = f"""{ssymbol}  Fail-Condition 2: Close Price Zscore Below Threshold
        Z-Score: {azscore:.2f}
        Z-Score Limit: {zlimit:.2f}
        """
            webhook = DiscordWebhook(url=WEBHOOK_URL, content=content)
            response = webhook.execute()
            if response and response.status_code in [200, 204]:
                print("Image Sent to Discord")
            else:
                print("Send Fail")
            continue

        plt.plot(x, close, color='red', label='Actual')
        # plt.plot(x, pol.predict(poly.fit_transform(x)),
        #         color='blue', label='PolyReg')
        plt.plot(x, lin.predict(x), color='green', label='LinReg')
        plt.xlabel('Days')
        plt.ylabel('Price')
        plt.legend()
        filename = "stockplot.png"
        plt.savefig(filename, dpi=300, bbox_inches='tight', facecolor='#ababab', transparent=True)
        plt.close() 

        content = f"""
        Close Price: ${cps[-1]:.2f}
        Close Price Z-Score: {azscore:.2f}
        Predicted Price: ${polyguess:.2f}
        """
        webhook = DiscordWebhook(url=WEBHOOK_URL, content=f"It's a great time to buy {ssymbol}") #
        with open(filename, "rb") as f:
            webhook.add_file(file=f.read(), filename=filename) #
        embed = DiscordEmbed(title=ssymbol, description=content, color="03b2f8")
        embed.set_image(url=f"attachment://{filename}")  #
        webhook.add_embed(embed)  
        response = webhook.execute() 
        os.remove(filename)

        if response and response.status_code in [200, 204]: 
            print(f"Image sent to Discord - {time.ctime()}")
        else:
            print(f"Failed to send image to Discord. Status code: {response.status_code if response else 'N/A'}")
            print(f"Response: {response.text if response else 'N/A'}")
    except Exception as e:
        print(f"An error occurred for {ssymbol}: {e}")
        continue