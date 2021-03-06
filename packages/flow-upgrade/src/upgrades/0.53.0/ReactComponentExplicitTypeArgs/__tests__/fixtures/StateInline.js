// @flow

import React from 'react';

class MyComponent extends React.Component {
  props: Props;
  state: {a: number, b: number, c: number} = {a: 1, b: 2, c: 3};

  defaultProps: T;
  static props: T;
  static state: T;
  a: T;
  b = 5;
  c: T = 5;
  method() {}
}

const expression = () =>
  class extends React.Component {
    props: Props;
    state: {a: number, b: number, c: number} = {a: 1, b: 2, c: 3};

    defaultProps: T;
    static props: T;
    static state: T;
    a: T;
    b = 5;
    c: T = 5;
    method() {}
  }
