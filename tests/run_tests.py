import unittest
import sys
import os

if __name__ == '__main__':
    # Configure path references
    test_dir = os.path.abspath(os.path.dirname(__file__))
    sys.path.insert(0, test_dir)
    sys.path.insert(0, os.path.abspath(os.path.join(test_dir, '../backend')))
    
    print("Discovering and running backend API tests...")
    loader = unittest.TestLoader()
    suite = loader.discover(start_dir=test_dir, pattern='test_*.py')
    
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)
    
    sys.exit(0 if result.wasSuccessful() else 1)
