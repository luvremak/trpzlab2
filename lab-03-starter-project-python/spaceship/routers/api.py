# Experiment 5: replacement for `spaceship/routers/api.py` in the Python
# starter project. It adds a `numpy` dependency and an endpoint that
# generates two random 10x10 matrices and multiplies them.
#
# To apply: overwrite spaceship/routers/api.py in the build context with
# this file, and use requirements-numpy.in as the dependency manifest.
#
# Endpoint:  GET /api/matrix
# Response:  {"matrix_a": [[...], ...],
#             "matrix_b": [[...], ...],
#             "product":  [[...], ...]}

from fastapi import APIRouter
import numpy as np

router = APIRouter()


@router.get('')
def hello_world() -> dict:
    return {'msg': 'Hello, World!'}


@router.get('/matrix')
def matrix_product() -> dict:
    """Generate two random 10x10 matrices and return their product."""
    matrix_a = np.random.rand(10, 10)
    matrix_b = np.random.rand(10, 10)
    product = np.matmul(matrix_a, matrix_b)
    return {
        'matrix_a': matrix_a.tolist(),
        'matrix_b': matrix_b.tolist(),
        'product': product.tolist(),
    }
