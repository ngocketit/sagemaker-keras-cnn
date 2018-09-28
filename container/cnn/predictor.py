import os
import json
import sys
import flask
import cv2
import numpy as np
from keras.models import load_model
import tensorflow as tf
import jsonpickle

prefix = '/opt/ml/'
model_path = os.path.join(prefix, 'model', 'kaggle_dogs_cats.h5')

class KaggleDogsCats(object):
    model = None
    graph = None

    @classmethod
    def get_model(cls):
        if cls.model is None:
            cls.model = load_model(model_path)
            cls.model._make_predict_function()
            cls.graph = tf.get_default_graph()

        return cls.model

    @classmethod
    def predict(cls, input):
        model = cls.get_model()

        if model is not None:
            with cls.graph.as_default():
                prediction = model.predict(input)
                return prediction[0][0]

        return None

app = flask.Flask(__name__)

@app.route('/ping', methods=['GET'])
def ping():
    model = KaggleDogsCats.get_model() is not None
    status = 200 if model else 404
    return flask.Response(response='\n', status=status, mimetype='application/json')


@app.route('/invocations', methods=['POST'])
def serve():
    if flask.request.content_type == 'image/jpeg':
        nparr = np.fromstring(flask.request.data, np.uint8)
        img = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
        img = np.reshape(img, (1, 150, 150, 3))
        prediction = KaggleDogsCats.predict(img)
        response = jsonpickle.encode(prediction)
        return flask.Response(response=response, status=200, mimetype='application/json')

    return flask.Response(response='This predictor only supports image/jpeg content type', status=415, mimetype='text/plain')


